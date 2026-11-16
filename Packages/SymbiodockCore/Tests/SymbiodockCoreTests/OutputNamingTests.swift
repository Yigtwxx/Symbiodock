import Foundation
import Testing
@testable import SymbiodockCore

struct OutputNamingTests {
    private let source = URL(fileURLWithPath: "/docs/report.docx")

    @Test func theOutputSitsBesideTheSourceWithANewExtension() {
        #expect(OutputNaming.output(for: source, pathExtension: "pdf") { _ in false }.path == "/docs/report.pdf")
    }

    @Test func aTakenNameGetsANumber() {
        #expect(
            OutputNaming.output(for: source, pathExtension: "pdf") { $0.path == "/docs/report.pdf" }.path
                == "/docs/report 2.pdf")
        #expect(
            OutputNaming.output(for: source, pathExtension: "pdf") {
                ["/docs/report.pdf", "/docs/report 2.pdf"].contains($0.path)
            }.path == "/docs/report 3.pdf")
    }

    @Test func anEmptyExtensionMakesAFolderName() {
        #expect(
            OutputNaming.output(for: URL(fileURLWithPath: "/a/Archive.zip"), pathExtension: "") { _ in false }
                .path == "/a/Archive")
    }

    @Test func aFolderGainsTheZipExtension() {
        #expect(
            OutputNaming.output(
                for: URL(fileURLWithPath: "/a/Photos", isDirectory: true), pathExtension: "zip"
            ) { _ in false }.path == "/a/Photos.zip")
    }

    @Test func pagesGoInAFolderNamedAfterTheStem() {
        let pdf = URL(fileURLWithPath: "/a/report.pdf")
        #expect(OutputNaming.pagesFolder(for: pdf) { _ in false }.path == "/a/report pages")
        #expect(
            OutputNaming.pagesFolder(for: pdf) { $0.path == "/a/report pages" }.path
                == "/a/report pages 2")
    }

    @Test func pageNamesPadToTheDigitsOfTheCount() {
        #expect(OutputNaming.pageName(stem: "report", index: 0, count: 3, pathExtension: "png") == "report-01.png")
        #expect(OutputNaming.pageName(stem: "report", index: 119, count: 120, pathExtension: "jpg") == "report-120.jpg")
    }

    @Test func theTemporaryNameIsHiddenBesideTheOutput() {
        #expect(
            OutputNaming.temporary(for: URL(fileURLWithPath: "/docs/report.pdf"), token: "ab12").path
                == "/docs/.ab12-report.pdf")
    }
}
