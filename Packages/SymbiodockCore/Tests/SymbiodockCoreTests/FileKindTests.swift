import Testing
@testable import SymbiodockCore

struct FileKindTests {
    @Test func recognisesKindsByExtensionIgnoringCase() {
        #expect(FileKind.of(pathExtension: "HEIC", isDirectory: false) == .image)
        #expect(FileKind.of(pathExtension: "pdf", isDirectory: false) == .pdf)
        #expect(FileKind.of(pathExtension: "mkv", isDirectory: false) == .video)
        #expect(FileKind.of(pathExtension: "dmg", isDirectory: false) == .archive)
        #expect(FileKind.of(pathExtension: "flac", isDirectory: false) == .audio)
        #expect(FileKind.of(pathExtension: "md", isDirectory: false) == .document)
    }

    @Test func aRichTextPackageIsADocument() {
        #expect(FileKind.of(pathExtension: "rtfd", isDirectory: true) == .document)
    }

    @Test func otherDirectoriesAreFolders() {
        #expect(FileKind.of(pathExtension: "", isDirectory: true) == .folder)
        #expect(FileKind.of(pathExtension: "app", isDirectory: true) == .folder)
    }

    @Test func anUnknownExtensionIsOther() {
        #expect(FileKind.of(pathExtension: "xyz", isDirectory: false) == .other)
        #expect(FileKind.of(pathExtension: "", isDirectory: false) == .other)
    }
}
