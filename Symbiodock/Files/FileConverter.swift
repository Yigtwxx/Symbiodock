import AVFoundation
import AppKit
import ImageIO
import PDFKit
import SymbiodockCore
import UniformTypeIdentifiers

/// A conversion that did not work. `message` is short, fixed text for the tile; a tool's own
/// output and any path stay out of it.
struct ConversionFailure: Error, Equatable {
    let message: String
}

/// Turns one file into another format with what macOS ships, writing beside the source.
struct FileConverter: Sendable {
    let runner: ToolRunner

    private static let toolLimit: Duration = .seconds(120)
    private static let audioLimit: Duration = .seconds(600)

    /// Writes the result next to the source and returns it. Throws `ConversionFailure`
    /// or `CancellationError`; in both cases nothing is left behind.
    @concurrent
    func convert(_ source: URL, isDirectory: Bool, to target: ConversionTarget) async throws
        -> (url: URL, isDirectory: Bool)
    {
        let fail = ConversionFailure(
            message: target.engine == .unzip ? "Couldn't unzip" : "Couldn't convert to \(target.label)")
        guard source.isFileURL, source.path.hasPrefix("/") else { throw fail }
        let source = source.standardizedFileURL
        let folder = source.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw ConversionFailure(message: "Can't write to this folder")
        }
        let ext = source.pathExtension.lowercased()
        let exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }

        // Pages are only known after the PDF opens: one page is a file, more are a folder.
        var pdf: PDFDocument?
        let final: URL
        var producesDirectory = target.engine == .unzip
        if case .pdfPages = target.engine {
            guard let document = PDFDocument(url: source), document.pageCount > 0 else { throw fail }
            pdf = document
            if document.pageCount > 1 {
                final = OutputNaming.pagesFolder(for: source, exists: exists)
                producesDirectory = true
            } else {
                final = OutputNaming.output(
                    for: source, pathExtension: target.pathExtension, exists: exists)
            }
        } else {
            final = OutputNaming.output(
                for: source, pathExtension: target.pathExtension, exists: exists)
        }
        let temp = OutputNaming.temporary(for: final, token: Self.token())

        do {
            try Task.checkCancellation()
            try await produce(
                target.engine, source: source, sourceExtension: ext, temp: temp, final: final,
                pdf: pdf, fail: fail)
            try Task.checkCancellation()
            guard exists(temp) else { throw fail }
            try FileManager.default.moveItem(at: temp, to: final)
            return (final, producesDirectory)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw (error as? ConversionFailure) ?? fail
        }
    }

    private static func token() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    private func produce(
        _ engine: ConversionEngine, source: URL, sourceExtension: String, temp: URL, final: URL,
        pdf: PDFDocument?, fail: ConversionFailure
    ) async throws {
        switch engine {
        case .sips, .textutil, .afconvert, .zip, .unzip:
            guard
                let command = ConversionCatalog.command(
                    for: engine, sourceExtension: sourceExtension, source: source.path,
                    output: temp.path)
            else { throw fail }
            let limit: Duration
            if case .afconvert = engine { limit = Self.audioLimit } else { limit = Self.toolLimit }
            guard await runner.run(command, timeLimit: limit) == 0 else { throw fail }
        case .printPDF:
            do {
                try await MainActor.run {
                    try DocumentPDFWriter.write(source, sourceExtension: sourceExtension, to: temp)
                }
            } catch { throw fail }
        case .pdfPages(let jpeg):
            guard let pdf else { throw fail }
            try Self.writePages(pdf, source: source, jpeg: jpeg, temp: temp, fail: fail)
        case .pdfText:
            guard let text = PDFDocument(url: source)?.string,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ConversionFailure(message: "No text in this PDF") }
            do { try Data(text.utf8).write(to: temp) } catch { throw fail }
        case .avExport(let audioOnly, let container):
            try await Self.export(source, audioOnly: audioOnly, container: container, to: temp,
                                  fail: fail)
        }
    }

    // MARK: PDF pages

    private static let pageDPI: CGFloat = 150

    private static func writePages(
        _ pdf: PDFDocument, source: URL, jpeg: Bool, temp: URL,
        fail: ConversionFailure
    ) throws {
        let count = pdf.pageCount
        let ext = jpeg ? "jpg" : "png"
        let type = (jpeg ? UTType.jpeg : UTType.png).identifier
        if count > 1 {
            do {
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
            } catch { throw fail }
        }
        let name = source.deletingPathExtension().lastPathComponent
        for index in 0..<count {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index), let image = render(page) else { throw fail }
            let destination =
                count > 1
                ? temp.appendingPathComponent(
                    OutputNaming.pageName(stem: name, index: index, count: count, pathExtension: ext))
                : temp
            guard
                let sink = CGImageDestinationCreateWithURL(destination as CFURL, type as CFString, 1, nil)
            else { throw fail }
            let properties: [CFString: Any] =
                jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] : [:]
            CGImageDestinationAddImage(sink, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(sink) else { throw fail }
        }
    }

    /// One page at 150 dpi on white; the media box is in points (72 per inch).
    private static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale = pageDPI / 72
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, width * height < 400_000_000,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: Video and audio export

    /// `AVAssetExportSession` is not `Sendable`; it is only handed to `cancelExport()`.
    private final class SessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }

    private static func export(
        _ source: URL, audioOnly: Bool, container: String, to temp: URL, fail: ConversionFailure
    ) async throws {
        let asset = AVURLAsset(url: source)
        let hasVideo: Bool
        do { hasVideo = try await !asset.loadTracks(withMediaType: .video).isEmpty } catch {
            throw fail
        }
        if !audioOnly && !hasVideo { throw fail }
        let preset = audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        let fileType: AVFileType =
            switch container {
            case "mp4": .mp4
            case "mov": .mov
            default: .m4a
            }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw fail }
        let box = SessionBox(session)

        try await withTaskCancellationHandler {
            if #available(macOS 15, *) {
                do { try await session.export(to: temp, as: fileType) } catch { throw fail }
            } else {
                session.outputURL = temp
                session.outputFileType = fileType
                await session.export()
                guard session.status == .completed else { throw fail }
            }
        } onCancel: {
            box.session.cancelExport()
        }
    }

    // MARK: Archive

    /// One `Archive.zip` holding all the sources, like Finder's Compress; next to the first source.
    func archive(_ sources: [URL]) async throws -> URL {
        let fail = ConversionFailure(message: "Couldn't convert to ZIP")
        guard sources.count >= 2, sources.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") })
        else { throw fail }
        let sources = sources.map(\.standardizedFileURL)
        let folder = sources[0].deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw ConversionFailure(message: "Can't write to this folder")
        }
        let manager = FileManager.default
        let final = OutputNaming.output(
            for: folder.appendingPathComponent("Archive"), pathExtension: "zip",
            exists: { manager.fileExists(atPath: $0.path) })
        let temp = OutputNaming.temporary(for: final, token: Self.token())
        let staging = manager.temporaryDirectory.appendingPathComponent(
            "symbiodock-archive-\(Self.token())", isDirectory: true)

        do {
            try Task.checkCancellation()
            try manager.createDirectory(at: staging, withIntermediateDirectories: false)
            var taken: Set<String> = []
            for source in sources {
                try Task.checkCancellation()
                let isFolder =
                    (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let stem = isFolder
                    ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
                let ext = isFolder ? "" : source.pathExtension
                var number = 1
                func name(_ n: Int) -> String {
                    let base = n == 1 ? stem : "\(stem) \(n)"
                    return ext.isEmpty ? base : "\(base).\(ext)"
                }
                while taken.contains(name(number)) { number += 1 }
                taken.insert(name(number))
                try manager.copyItem(at: source, to: staging.appendingPathComponent(name(number)))
            }
            let command = ToolCommand(
                tool: "/usr/bin/ditto",
                arguments: ["-c", "-k", "--sequesterRsrc", staging.path, temp.path])
            guard await runner.run(command, timeLimit: Self.toolLimit) == 0 else { throw fail }
            try Task.checkCancellation()
            guard manager.fileExists(atPath: temp.path) else { throw fail }
            try manager.moveItem(at: temp, to: final)
            try? manager.removeItem(at: staging)
            return final
        } catch {
            try? manager.removeItem(at: temp)
            try? manager.removeItem(at: staging)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw (error as? ConversionFailure) ?? fail
        }
    }
}
