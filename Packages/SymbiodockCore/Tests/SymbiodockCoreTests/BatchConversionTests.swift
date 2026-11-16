import Foundation
import Testing
@testable import SymbiodockCore

struct BatchConversionTests {
    private func item(_ name: String, dir: Bool = false) -> ShelfItem {
        ShelfItem(url: URL(fileURLWithPath: "/x/\(name)"), isDirectory: dir)
    }

    private func labels(_ names: String...) -> [String] {
        ConversionCatalog.commonLabels(names.map { item($0) })
    }

    // MARK: Common chips

    @Test func oneFileKeepsItsOwnChips() {
        #expect(labels("a.docx") == ["PDF", "RTF", "TXT", "HTML", "ODT", "ZIP"])
        #expect(labels("a.zip") == ["Unzip"])
        #expect(labels("a.mkv") == ["ZIP"])
    }

    @Test func twoDocxAndAPptxOfferPDFAndEndWithZIP() {
        let result = labels("a.docx", "b.docx", "c.pptx")
        #expect(result == ["PDF", "RTF", "TXT", "HTML", "ODT", "ZIP"])
        #expect(result.first == "PDF")
        #expect(result.last == "ZIP")
    }

    @Test func aFileAlreadyInTheFormatDoesNotRemoveItsChip() {
        // The PDF is already a PDF, so PDF stays; RTF and the rest are not offered by it.
        #expect(labels("a.docx", "b.pdf") == ["PDF", "TXT", "ZIP"])
    }

    @Test func pngAndJpgOfferBothImageFormatsEachSkippingItsOwn() {
        #expect(
            labels("a.png", "b.jpg")
                == ["JPEG", "HEIC", "TIFF", "GIF", "BMP", "PDF", "PNG", "ZIP"])
        #expect(labels("a.png", "b.jpeg").contains("JPEG"))
    }

    @Test func aDocxAndAPngShareOnlyPDF() {
        #expect(labels("a.docx", "b.png") == ["PDF", "ZIP"])
    }

    @Test func onlyZipsOfferUnzip() {
        #expect(labels("a.zip", "b.zip") == ["Unzip"])
    }

    @Test func nothingConvertibleLeavesJustZIP() {
        #expect(labels("a.pptx", "b.mkv") == ["ZIP"])
        #expect(ConversionCatalog.commonLabels([item("Photos", dir: true), item("a.pptx")]) == ["ZIP"])
    }

    @Test func zipsDoNotTakePartInTheCommonChips() {
        #expect(labels("a.zip", "b.png", "c.jpg") == ConversionCatalog.commonLabels([item("b.png"), item("c.jpg")]))
    }

    @Test func noFilesNoChips() {
        #expect(ConversionCatalog.commonLabels([]).isEmpty)
    }

    // MARK: Plans

    @Test func theOwnersCaseConvertsTheDocxAndSaysThePptxCannot() {
        let (a, b, c) = (item("a.docx"), item("b.docx"), item("c.pptx"))
        let plan = ConversionCatalog.plan(label: "PDF", items: [a, b, c])
        #expect(Set(plan.targets.keys) == [a.id, b.id])
        #expect(plan.targets[a.id]?.engine == .printPDF)
        #expect(plan.unsupported == [c.id])
        #expect(plan.already.isEmpty)
        #expect(!plan.archive)
    }

    @Test func eachFileUsesItsOwnEngine() {
        let (docx, png) = (item("a.docx"), item("b.png"))
        let plan = ConversionCatalog.plan(label: "PDF", items: [docx, png])
        #expect(plan.targets[docx.id]?.engine == .printPDF)
        #expect(plan.targets[png.id]?.engine == .sips(format: "pdf"))
    }

    @Test func aFileAlreadyInTheFormatIsSkippedSilently() {
        let (doc, pdf, png, jpg) = (item("a.docx"), item("b.pdf"), item("c.png"), item("d.jpeg"))
        let plan = ConversionCatalog.plan(label: "PDF", items: [doc, pdf])
        #expect(Set(plan.targets.keys) == [doc.id])
        #expect(plan.already == [pdf.id])
        #expect(plan.unsupported.isEmpty)
        let images = ConversionCatalog.plan(label: "JPEG", items: [png, jpg])
        #expect(Set(images.targets.keys) == [png.id])
        #expect(images.already == [jpg.id])
    }

    @Test func zipOfSeveralIsOneArchive() {
        let items = [item("a.docx"), item("b.png"), item("Photos", dir: true)]
        let plan = ConversionCatalog.plan(label: "ZIP", items: items)
        #expect(plan.archive)
        #expect(plan.targets.isEmpty)
        #expect(plan.already.isEmpty)
        #expect(plan.unsupported.isEmpty)
    }

    @Test func zipOfOneFileIsAnOrdinaryConversion() {
        let a = item("a.docx")
        let plan = ConversionCatalog.plan(label: "ZIP", items: [a])
        #expect(!plan.archive)
        #expect(plan.targets[a.id]?.engine == .zip)
    }

    @Test func unzipTakesOnlyZips() {
        let (z, d) = (item("a.zip"), item("b.docx"))
        let plan = ConversionCatalog.plan(label: "Unzip", items: [z, d])
        #expect(Set(plan.targets.keys) == [z.id])
        #expect(plan.targets[z.id]?.engine == .unzip)
        #expect(plan.unsupported == [d.id])
        // A file without an extension is not "already" a folder.
        let bare = ConversionCatalog.plan(label: "Unzip", items: [item("Makefile")])
        #expect(bare.unsupported.count == 1)
        #expect(bare.already.isEmpty)
    }

    @Test func aLabelNobodyOffersLeavesEveryoneUnsupportedOrAlready() {
        let (a, b) = (item("a.mkv"), item("b.pdf"))
        let plan = ConversionCatalog.plan(label: "PDF", items: [a, b])
        #expect(plan.targets.isEmpty)
        #expect(plan.unsupported == [a.id])
        #expect(plan.already == [b.id])
        let unknown = ConversionCatalog.plan(label: "Nonsense", items: [a])
        #expect(unknown.unsupported == [a.id])
    }

    // MARK: Notice text

    @Test func batchTextNamesOneFileOrCountsSeveral() {
        #expect(
            ShelfNotice.batchText(label: "PDF", unsupported: ["Slides.pptx"], failed: 0)
                == "Slides.pptx can't become PDF")
        #expect(
            ShelfNotice.batchText(label: "PDF", unsupported: ["a.pptx", "b.mkv"], failed: 0)
                == "2 files can't become PDF")
    }

    @Test func batchTextReportsFailures() {
        #expect(
            ShelfNotice.batchText(label: "PDF", unsupported: [], failed: 1)
                == "Couldn't convert 1 file")
        #expect(
            ShelfNotice.batchText(label: "PDF", unsupported: [], failed: 3)
                == "Couldn't convert 3 files")
    }

    @Test func batchTextJoinsBothAndIsNilWithNothingToSay() {
        #expect(
            ShelfNotice.batchText(label: "PNG", unsupported: ["a.pptx"], failed: 2)
                == "a.pptx can't become PNG · Couldn't convert 2 files")
        #expect(ShelfNotice.batchText(label: "PDF", unsupported: [], failed: 0) == nil)
    }
}
