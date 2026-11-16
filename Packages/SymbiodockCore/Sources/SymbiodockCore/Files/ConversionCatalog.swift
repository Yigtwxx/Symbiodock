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

public enum ConversionCatalog {
    private static func target(_ label: String, _ ext: String, _ engine: ConversionEngine)
        -> ConversionTarget
    {
        ConversionTarget(label: label, pathExtension: ext, engine: engine)
    }

    private static let zip = target("ZIP", "zip", .zip)

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
        target("M4A", "m4a", .afconvert(file: "m4af", data: "aac", bitrate: 256_000)),
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
        if ext == "zip" { return [target("Unzip", "", .unzip)] }
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
