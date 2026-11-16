import Foundation

/// The system tool, or in-process routine, that makes one target.
public enum ConversionEngine: Equatable, Sendable {
    case sips(format: String)
    case textutil(format: String)
    case printPDF
    case pdfPages(jpeg: Bool)
    case pdfText
    case afconvert(file: String, data: String, bitrate: Int?)
    /// `container` is "mp4", "mov" or "m4a".
    case avExport(audioOnly: Bool, container: String)
    case zip
    case unzip
}

/// One chip on the tile: what a file can become.
public struct ConversionTarget: Identifiable, Equatable, Sendable {
    /// The chip: "PDF", "JPEG", "Unzip".
    public let label: String
    /// "pdf", "jpg"; empty for Unzip, which makes a folder.
    public let pathExtension: String
    public let engine: ConversionEngine
    public var id: String { label }

    public init(label: String, pathExtension: String, engine: ConversionEngine) {
        self.label = label
        self.pathExtension = pathExtension
        self.engine = engine
    }
}

/// A tool to run by absolute path with an argument array, never through a shell.
public struct ToolCommand: Equatable, Sendable {
    public let tool: String
    public let arguments: [String]

    public init(tool: String, arguments: [String]) {
        self.tool = tool
        self.arguments = arguments
    }
}

/// What each kind of file can become, and the commands that make it.
public enum ConversionCatalog {
    private static func target(_ label: String, _ ext: String, _ engine: ConversionEngine)
        -> ConversionTarget
    {
        ConversionTarget(label: label, pathExtension: ext, engine: engine)
    }

    private static let zip = target("ZIP", "zip", .zip)
    private static let unzip = target("Unzip", "", .unzip)

    private static let imageTargets = [
        target("PNG", "png", .sips(format: "png")),
        target("JPEG", "jpg", .sips(format: "jpeg")),
        target("HEIC", "heic", .sips(format: "heic")),
        target("TIFF", "tiff", .sips(format: "tiff")),
        target("GIF", "gif", .sips(format: "gif")),
        target("BMP", "bmp", .sips(format: "bmp")),
        target("PDF", "pdf", .sips(format: "pdf")),
    ]

    private static let documentTargets =
        [target("PDF", "pdf", .printPDF)]
        + ["DOCX", "RTF", "TXT", "HTML", "ODT"].map {
            target($0, $0.lowercased(), .textutil(format: $0.lowercased()))
        }

    private static let pdfTargets = [
        target("PNG", "png", .pdfPages(jpeg: false)),
        target("JPEG", "jpg", .pdfPages(jpeg: true)),
        target("TXT", "txt", .pdfText),
    ]

    private static let audioTargets = [
        target("M4A", "m4a", .afconvert(file: "m4af", data: "aac", bitrate: nil)),
        target("WAV", "wav", .afconvert(file: "WAVE", data: "LEI16", bitrate: nil)),
        target("AIFF", "aiff", .afconvert(file: "AIFF", data: "BEI16", bitrate: nil)),
        target("FLAC", "flac", .afconvert(file: "flac", data: "flac", bitrate: nil)),
    ]

    private static let videoTargets = [
        target("MP4", "mp4", .avExport(audioOnly: false, container: "mp4")),
        target("MOV", "mov", .avExport(audioOnly: false, container: "mov")),
        target("M4A", "m4a", .avExport(audioOnly: true, container: "m4a")),
    ]

    /// Extensions that name the same format count as one when a target equal to the source
    /// is left out.
    private static func family(_ ext: String) -> String {
        switch ext {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        case "heif": return "heic"
        case "aif": return "aiff"
        case "htm": return "html"
        default: return ext
        }
    }

    /// What the file can become, in chip order. The archive target ends every list.
    public static func targets(pathExtension: String, isDirectory: Bool) -> [ConversionTarget] {
        let ext = pathExtension.lowercased()
        if isDirectory && ext != "rtfd" { return [zip] }
        if ext == "zip" { return [unzip] }
        let base: [ConversionTarget]
        if FileExtensions.image.contains(ext) {
            base = imageTargets
        } else if FileExtensions.document.contains(ext) {
            base = documentTargets
        } else if ext == "pdf" {
            base = pdfTargets
        } else if ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"].contains(ext) {
            base = audioTargets
        } else if ["mov", "mp4", "m4v"].contains(ext) {
            base = videoTargets
        } else {
            base = []
        }
        return base.filter { family($0.pathExtension) != family(ext) } + [zip]
    }

    /// Nil for engines that run in-process (printPDF, pdfPages, pdfText, avExport).
    public static func command(
        for engine: ConversionEngine, sourceExtension: String, source: String, output: String
    ) -> ToolCommand? {
        switch engine {
        case .sips(let format):
            let quality = format == "jpeg" || format == "heic" ? ["-s", "formatOptions", "90"] : []
            return ToolCommand(
                tool: "/usr/bin/sips",
                arguments: ["-s", "format", format] + quality + [source, "--out", output])
        case .textutil(let format):
            let input = sourceExtension == "md" ? ["-format", "txt"] : []
            return ToolCommand(
                tool: "/usr/bin/textutil",
                arguments: ["-convert", format] + input + ["-output", output, source])
        case .afconvert(let file, let data, let bitrate):
            let rate = bitrate.map { ["-b", "\($0)"] } ?? []
            return ToolCommand(
                tool: "/usr/bin/afconvert",
                arguments: [source, "-o", output, "-f", file, "-d", data] + rate)
        case .zip:
            return ToolCommand(
                tool: "/usr/bin/ditto",
                arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", source, output])
        case .unzip:
            return ToolCommand(tool: "/usr/bin/ditto", arguments: ["-x", "-k", source, output])
        case .printPDF, .pdfPages, .pdfText, .avExport:
            return nil
        }
    }
}

/// What a batch of files will do for one chip.
public struct BatchPlan: Equatable, Sendable {
    /// Files to convert, each with its own engine.
    public var targets: [UUID: ConversionTarget] = [:]
    /// Already that format: skipped silently.
    public var already: [UUID] = []
    /// Cannot become that: skipped, and said.
    public var unsupported: [UUID] = []
    /// Several files and "ZIP": one `Archive.zip`, `targets` empty.
    public var archive = false
}

extension ConversionCatalog {
    /// Every target the catalog can make, for finding what a label means.
    private static let everyTarget =
        imageTargets + documentTargets + pdfTargets + audioTargets + videoTargets + [zip, unzip]

    /// The chips for several files at once. One file keeps its own. Of several, a target is
    /// offered when every "convertible" file (one with a target besides ZIP and Unzip) offers
    /// it or already is that format, and at least one offers it; ZIP comes last. Only zips
    /// leave just Unzip.
    public static func commonLabels(_ items: [ShelfItem]) -> [String] {
        let offered = items.map { targets(pathExtension: $0.url.pathExtension, isDirectory: $0.isDirectory) }
        if items.count < 2 { return offered.first?.map(\.label) ?? [] }
        if offered.allSatisfy({ $0.map(\.label) == [unzip.label] }) { return [unzip.label] }
        let convertible = items.indices.filter { index in
            offered[index].contains { $0.label != zip.label && $0.label != unzip.label }
        }
        var candidates: [ConversionTarget] = []
        for index in convertible {
            for target in offered[index]
            where target.label != zip.label && !candidates.contains(where: { $0.label == target.label }) {
                candidates.append(target)
            }
        }
        let common = candidates.filter { candidate in
            var offeredByOne = false
            for index in convertible {
                if offered[index].contains(where: { $0.label == candidate.label }) {
                    offeredByOne = true
                } else if !isAlready(items[index], candidate) {
                    return false
                }
            }
            return offeredByOne
        }
        return common.map(\.label) + [zip.label]
    }

    /// What pressing `label` does to each file. Several files and ZIP make one archive.
    public static func plan(label: String, items: [ShelfItem]) -> BatchPlan {
        var plan = BatchPlan()
        if items.count > 1 && label == zip.label {
            plan.archive = true
            return plan
        }
        let wanted = everyTarget.first { $0.label == label }
        for item in items {
            let own = targets(pathExtension: item.url.pathExtension, isDirectory: item.isDirectory)
            if let target = own.first(where: { $0.label == label }) {
                plan.targets[item.id] = target
            } else if let wanted, isAlready(item, wanted) {
                plan.already.append(item.id)
            } else {
                plan.unsupported.append(item.id)
            }
        }
        return plan
    }

    /// The file already is the format of the target (a folder or a file without an extension
    /// is never "already" Unzip's empty extension).
    private static func isAlready(_ item: ShelfItem, _ target: ConversionTarget) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        return !target.pathExtension.isEmpty && !item.isDirectory
            && family(ext) == family(target.pathExtension)
    }
}

extension ShelfNotice {
    /// "Slides.pptx can't become PDF", "2 files can't become PDF", "Couldn't convert 1 file",
    /// both joined with " · "; nil when there is nothing to say.
    public static func batchText(label: String, unsupported: [String], failed: Int) -> String? {
        var parts: [String] = []
        if unsupported.count == 1 {
            parts.append("\(unsupported[0]) can't become \(label)")
        } else if unsupported.count > 1 {
            parts.append("\(unsupported.count) files can't become \(label)")
        }
        if failed > 0 { parts.append("Couldn't convert \(failed) file\(failed == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
