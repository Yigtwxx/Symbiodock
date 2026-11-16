import Testing
@testable import SymbiodockCore

struct ConversionCatalogTests {
    private func labels(_ ext: String, dir: Bool = false) -> [String] {
        ConversionCatalog.targets(pathExtension: ext, isDirectory: dir).map(\.label)
    }

    @Test func imagesConvertToOtherImageFormatsAndPDF() {
        #expect(labels("png") == ["JPEG", "HEIC", "TIFF", "GIF", "BMP", "PDF", "ZIP"])
        #expect(labels("JPG") == ["PNG", "HEIC", "TIFF", "GIF", "BMP", "PDF", "ZIP"])
    }

    @Test func documentsLeaveOutTheirOwnFormatFamily() {
        #expect(labels("docx") == ["PDF", "RTF", "TXT", "HTML", "ODT", "ZIP"])
        #expect(labels("htm") == ["PDF", "DOCX", "RTF", "TXT", "ODT", "ZIP"])
    }

    @Test func pdfsBecomePagesOrText() {
        #expect(labels("pdf") == ["PNG", "JPEG", "TXT", "ZIP"])
    }

    @Test func audioAndVideoOfferWhatTheSystemToolsCanMake() {
        #expect(labels("aif") == ["M4A", "WAV", "FLAC", "ZIP"])
        #expect(labels("mp3") == ["M4A", "WAV", "AIFF", "FLAC", "ZIP"])
        #expect(labels("mov") == ["MP4", "M4A", "ZIP"])
        #expect(labels("mkv") == ["ZIP"])
        #expect(labels("ogg") == ["ZIP"])
    }

    @Test func archivesUnzipAndFoldersZip() {
        #expect(labels("zip") == ["Unzip"])
        #expect(labels("", dir: true) == ["ZIP"])
        #expect(labels("png", dir: true) == ["ZIP"])
        #expect(labels("rtfd", dir: true) == ["PDF", "DOCX", "RTF", "TXT", "HTML", "ODT", "ZIP"])
        #expect(labels("xyz") == ["ZIP"])
    }

    @Test func unzipMakesAFolderName() {
        let target = ConversionCatalog.targets(pathExtension: "zip", isDirectory: false)[0]
        #expect(target.pathExtension == "")
        #expect(target.engine == .unzip)
    }

    @Test func sipsCommandAddsQualityForLossyFormats() {
        #expect(
            ConversionCatalog.command(
                for: .sips(format: "jpeg"), sourceExtension: "png", source: "/a/b.png",
                output: "/a/.t-b.jpg")
                == ToolCommand(
                    tool: "/usr/bin/sips",
                    arguments: [
                        "-s", "format", "jpeg", "-s", "formatOptions", "90", "/a/b.png", "--out",
                        "/a/.t-b.jpg",
                    ]))
        #expect(
            ConversionCatalog.command(
                for: .sips(format: "png"), sourceExtension: "jpg", source: "/a/b.jpg",
                output: "/a/.t-b.png")?.arguments
                == ["-s", "format", "png", "/a/b.jpg", "--out", "/a/.t-b.png"])
    }

    @Test func textutilReadsMarkdownAsPlainText() {
        #expect(
            ConversionCatalog.command(
                for: .textutil(format: "docx"), sourceExtension: "md", source: "/a/n.md",
                output: "/a/.t-n.docx")
                == ToolCommand(
                    tool: "/usr/bin/textutil",
                    arguments: [
                        "-convert", "docx", "-format", "txt", "-output", "/a/.t-n.docx", "/a/n.md",
                    ]))
    }

    @Test func afconvertCarriesTheBitrateOnlyWhenGiven() {
        #expect(
            ConversionCatalog.command(
                for: .afconvert(file: "m4af", data: "aac", bitrate: 256_000),
                sourceExtension: "wav", source: "/a/s.wav", output: "/a/.t-s.m4a")
                == ToolCommand(
                    tool: "/usr/bin/afconvert",
                    arguments: [
                        "/a/s.wav", "-o", "/a/.t-s.m4a", "-f", "m4af", "-d", "aac", "-b", "256000",
                    ]))
        #expect(
            ConversionCatalog.command(
                for: .afconvert(file: "WAVE", data: "LEI16", bitrate: nil),
                sourceExtension: "mp3", source: "/a/s.mp3", output: "/a/.t-s.wav")?.arguments
                == ["/a/s.mp3", "-o", "/a/.t-s.wav", "-f", "WAVE", "-d", "LEI16"])
    }

    @Test func m4aLeavesTheBitrateToAfconvert() {
        // A fixed 256 kbps is refused for mono or low-sample-rate sources (voice memos).
        let m4a = ConversionCatalog.targets(pathExtension: "wav", isDirectory: false)
            .first { $0.label == "M4A" }
        #expect(m4a?.engine == .afconvert(file: "m4af", data: "aac", bitrate: nil))
    }

    @Test func dittoZipsAndUnzips() {
        #expect(
            ConversionCatalog.command(
                for: .zip, sourceExtension: "", source: "/a/Photos", output: "/a/.t-Photos.zip")
                == ToolCommand(
                    tool: "/usr/bin/ditto",
                    arguments: [
                        "-c", "-k", "--sequesterRsrc", "--keepParent", "/a/Photos",
                        "/a/.t-Photos.zip",
                    ]))
        #expect(
            ConversionCatalog.command(
                for: .unzip, sourceExtension: "zip", source: "/a/x.zip", output: "/a/.t-x")
                == ToolCommand(
                    tool: "/usr/bin/ditto", arguments: ["-x", "-k", "/a/x.zip", "/a/.t-x"]))
    }

    @Test func inProcessEnginesHaveNoCommand() {
        let engines: [ConversionEngine] = [
            .printPDF, .pdfPages(jpeg: true), .pdfText, .avExport(audioOnly: true, container: "m4a"),
        ]
        for engine in engines {
            #expect(
                ConversionCatalog.command(
                    for: engine, sourceExtension: "docx", source: "/a", output: "/b") == nil)
        }
    }

    @Test func aPathThatLooksLikeAnOptionStaysOneArgument() {
        let command = ConversionCatalog.command(
            for: .zip, sourceExtension: "", source: "-rf", output: "/a/.t-x.zip")
        #expect(command?.arguments.filter { $0 == "-rf" }.count == 1)
        #expect(command?.arguments.contains("-rf") == true)
    }
}
