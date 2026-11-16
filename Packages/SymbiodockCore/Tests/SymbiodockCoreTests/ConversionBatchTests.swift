import Foundation
import Testing
@testable import SymbiodockCore

struct ConversionBatchTests {
    private func item(_ name: String, stack: UUID? = nil) -> ShelfItem {
        let isDirectory = name.hasSuffix("/")
        return ShelfItem(
            url: URL(fileURLWithPath: "/x/\(name.trimmingCharacters(in: ["/"]))"),
            isDirectory: isDirectory, stack: stack)
    }

    /// A drawer of the first names, then the rest as lone tiles.
    private func shelf(stacked: [ShelfItem], lone: [ShelfItem] = []) -> FileShelf {
        FileShelf(items: stacked + lone)
    }

    private func batch(_ label: String, _ items: [ShelfItem], busy: Set<UUID> = []) -> ConversionBatch {
        ConversionBatch(label: label, ids: items.map(\.id), shelf: FileShelf(items: items), busy: busy)
    }

    private let pdf = URL(fileURLWithPath: "/x/out.pdf")
    private var converted: ConversionResult { .converted(url: pdf, isDirectory: false) }

    // MARK: What it covers

    @Test func itCoversTheFilesThatOfferTheChipInShelfOrder() {
        let drawer = UUID()
        let (a, b, c) = (item("a.docx", stack: drawer), item("b.docx", stack: drawer), item("c.pptx", stack: drawer))
        let d = item("d.png")
        let shelf = shelf(stacked: [a, b, c], lone: [d])
        let batch = ConversionBatch(label: "PDF", ids: [d.id, c.id, a.id, b.id], shelf: shelf, busy: [])
        #expect(batch.files == [a.id, b.id, d.id])
        #expect(batch.targets[a.id]?.engine == .printPDF)
        #expect(batch.targets[d.id]?.engine == .sips(format: "pdf"))
        #expect(!batch.isArchive)
        #expect(!batch.isEmpty)
    }

    @Test func filesAlreadyConvertingOrNotHeldAreLeftOut() {
        let (a, b) = (item("a.png"), item("b.png"))
        let batch = ConversionBatch(
            label: "JPEG", ids: [a.id, b.id, UUID()], shelf: FileShelf(items: [a, b]), busy: [a.id])
        #expect(batch.files == [b.id])
    }

    @Test func nothingFreeToConvertIsEmptyAndSaysNothing() {
        let a = item("a.png")
        let batch = batch("JPEG", [a], busy: [a.id])
        #expect(batch.isEmpty)
        #expect(batch.notice(held: [a.id]) == nil)
    }

    @Test func somethingUnsupportedAndNothingToConvertSaysSoAtOnce() {
        let c = item("Slides.pptx")
        let batch = batch("PDF", [c])
        #expect(batch.isEmpty)
        #expect(batch.isDecided)
        #expect(batch.notice(held: [c.id]) == ShelfNotice(id: c.id, text: "Slides.pptx can't become PDF"))
    }

    @Test func filesAlreadyInTheFormatAreSkippedSilently() {
        let (a, b) = (item("a.docx"), item("b.pdf"))
        let batch = batch("PDF", [a, b])
        #expect(batch.files == [a.id])
        #expect(batch.isDecided == false)
    }

    @Test func itHoldsOnlyTheFilesItCovers() {
        let (a, b) = (item("a.png"), item("b.pptx"))
        let batch = batch("JPEG", [a, b])
        #expect(batch.holds(any: [UUID(), a.id]))
        #expect(!batch.holds(any: [b.id]))
        #expect(!batch.holds(any: []))
    }

    // MARK: When tiles open

    @Test func aLoneTileOpensAsSoonAsItsOwnFileIsDone() {
        let (a, b) = (item("a.png"), item("b.png"))
        var batch = batch("JPEG", [a, b])
        #expect(batch.record(a.id, converted) == [[.reveal(a.id, converted)]])
        #expect(!batch.isDecided)
        #expect(batch.record(b.id, .failed("Couldn't convert to JPEG")) == [[.reveal(b.id, .failed("Couldn't convert to JPEG"))]])
        #expect(batch.isDecided)
    }

    @Test func theFilesOfAStackOpenTogetherWhenTheLastIsDoneEachWithItsOwnResult() {
        let drawer = UUID()
        let (a, b) = (item("a.docx", stack: drawer), item("b.docx", stack: drawer))
        let c = item("c.png")
        var batch = ConversionBatch(
            label: "PDF", ids: [a.id, b.id, c.id], shelf: shelf(stacked: [a, b], lone: [c]), busy: [])
        #expect(batch.record(a.id, converted).isEmpty)
        #expect(batch.record(c.id, .cancelled) == [[.reveal(c.id, .cancelled)]])
        #expect(batch.record(b.id, .failed("x")) == [[.reveal(a.id, converted), .reveal(b.id, .failed("x"))]])
    }

    @Test func aStacksFileThatDoesNotConvertIsNotWaitedFor() {
        let drawer = UUID()
        let (a, b, c) = (item("a.docx", stack: drawer), item("b.docx", stack: drawer), item("c.pptx", stack: drawer))
        var batch = ConversionBatch(
            label: "PDF", ids: [a.id, b.id, c.id], shelf: shelf(stacked: [a, b, c]), busy: [])
        #expect(batch.record(a.id, converted).isEmpty)
        #expect(batch.record(b.id, converted) == [[.reveal(a.id, converted), .reveal(b.id, converted)]])
    }

    @Test func aFileKeepsItsFirstResultAndUnknownFilesAreIgnored() {
        let a = item("a.png")
        var batch = batch("JPEG", [a])
        #expect(batch.record(a.id, converted).count == 1)
        #expect(batch.record(a.id, .cancelled).isEmpty)
        #expect(batch.record(UUID(), converted).isEmpty)
    }

    // MARK: Cancel

    @Test func aCancelOpensWhatWaitsUnchangedAndKeepsWhatWasConverted() {
        let drawer = UUID()
        let (a, b, c) = (item("a.docx", stack: drawer), item("b.docx", stack: drawer), item("c.docx", stack: drawer))
        let d = item("d.docx")
        var batch = ConversionBatch(
            label: "PDF", ids: [a.id, b.id, c.id, d.id], shelf: shelf(stacked: [a, b, c], lone: [d]), busy: [])
        #expect(batch.record(a.id, converted).isEmpty)
        let opened = batch.cancelRemaining()
        #expect(
            opened == [
                [.reveal(a.id, converted), .reveal(b.id, .cancelled), .reveal(c.id, .cancelled)],
                [.reveal(d.id, .cancelled)],
            ])
        #expect(batch.isDecided)
        #expect(batch.cancelRemaining().isEmpty)
    }

    @Test func aCancelDoesNotReopenTilesAlreadyOpened() {
        let (a, b) = (item("a.png"), item("b.png"))
        var batch = batch("JPEG", [a, b])
        _ = batch.record(a.id, converted)
        #expect(batch.cancelRemaining() == [[.reveal(b.id, .cancelled)]])
    }

    // MARK: Archive

    @Test func anArchiveCoversEveryListedFileAndOpensAsOne() {
        let (a, b, c) = (item("a.docx"), item("b.png"), item("Photos/"))
        var batch = batch("ZIP", [a, b, c])
        #expect(batch.isArchive)
        #expect(batch.files == [a.id, b.id, c.id])
        #expect(batch.targets.isEmpty)
        let zip = ConversionResult.converted(url: URL(fileURLWithPath: "/x/Archive.zip"), isDirectory: false)
        #expect(batch.recordArchive(zip) == [[.reveal(a.id, zip), .leave(b.id), .leave(c.id)]])
        #expect(batch.isDecided)
        #expect(batch.notice(held: [a.id]) == nil)
        #expect(batch.recordArchive(zip).isEmpty)
    }

    @Test func aFailedArchiveOpensEveryTileUnchangedAndTheFirstSaysWhy() {
        let (a, b) = (item("a.docx"), item("b.png"))
        var batch = batch("ZIP", [a, b])
        let failed = ConversionResult.failed("Can't write to this folder")
        #expect(batch.recordArchive(failed) == [[.reveal(a.id, failed), .reveal(b.id, .cancelled)]])
        #expect(batch.notice(held: [a.id, b.id]) == nil)
    }

    @Test func aCancelledArchiveOpensEveryTileUnchanged() {
        let (a, b) = (item("a.docx"), item("b.png"))
        var batch = batch("ZIP", [a, b])
        #expect(batch.cancelRemaining() == [[.reveal(a.id, .cancelled), .reveal(b.id, .cancelled)]])
    }

    @Test func oneFilesRecordIsNotAnArchivesAndTheOtherWayRound() {
        let (a, b) = (item("a.png"), item("b.png"))
        var files = batch("JPEG", [a, b])
        #expect(files.recordArchive(converted).isEmpty)
        var archive = batch("ZIP", [a, b])
        #expect(archive.record(a.id, converted).isEmpty)
    }

    // MARK: The notice when it is over

    @Test func theOwnersBatchNamesThePptxOnTheFirstFile() {
        let drawer = UUID()
        let (a, b, c) = (item("Report.docx", stack: drawer), item("Notes.docx", stack: drawer), item("Slides.pptx", stack: drawer))
        var batch = ConversionBatch(
            label: "PDF", ids: [a.id, b.id, c.id], shelf: shelf(stacked: [a, b, c]), busy: [])
        _ = batch.record(a.id, converted)
        _ = batch.record(b.id, converted)
        #expect(batch.notice(held: [a.id, b.id, c.id]) == ShelfNotice(id: a.id, text: "Slides.pptx can't become PDF"))
    }

    @Test func aBatchCountsItsFailures() {
        let (a, b, c) = (item("a.png"), item("b.png"), item("c.png"))
        var batch = batch("JPEG", [a, b, c])
        _ = batch.record(a.id, .failed("Couldn't convert to JPEG"))
        _ = batch.record(b.id, converted)
        _ = batch.record(c.id, .failed("Can't write to this folder"))
        #expect(batch.notice(held: [a.id, b.id, c.id])?.text == "Couldn't convert 2 files")
    }

    @Test func oneFileAloneSaysItsOwnFailureAsItOpens() {
        let a = item("a.png")
        var alone = batch("JPEG", [a])
        _ = alone.record(a.id, .failed("Can't write to this folder"))
        #expect(alone.notice(held: [a.id]) == nil)
        // A file already that format does not make it a batch.
        var withAlready = batch("JPEG", [a, item("b.jpg")])
        _ = withAlready.record(a.id, .failed("x"))
        #expect(withAlready.notice(held: [a.id]) == nil)
    }

    @Test func theNoticeHangsOnTheFirstListedFileStillHeld() {
        let (a, b) = (item("a.pptx"), item("b.mkv"))
        let batch = batch("PDF", [a, b])
        #expect(batch.notice(held: [a.id, b.id]) == ShelfNotice(id: a.id, text: "2 files can't become PDF"))
        #expect(batch.notice(held: [b.id])?.id == b.id)
        #expect(batch.notice(held: []) == nil)
    }

    @Test func aBatchThatWentWellSaysNothing() {
        let (a, b) = (item("a.png"), item("b.png"))
        var batch = batch("JPEG", [a, b])
        _ = batch.record(a.id, converted)
        _ = batch.record(b.id, .cancelled)
        #expect(batch.notice(held: [a.id, b.id]) == nil)
    }

    // MARK: Timing, demo and the column

    @Test func thePrinterStartsOnlyOnceTheCoverHasClosed() {
        #expect(ConversionBatch.startDelay(for: .printPDF, elapsed: 0) == EngulfTiming.engulf)
        #expect(abs(ConversionBatch.startDelay(for: .printPDF, elapsed: 0.2) - 0.5) < 1e-9)
        #expect(ConversionBatch.startDelay(for: .printPDF, elapsed: 3) == 0)
        #expect(ConversionBatch.startDelay(for: .sips(format: "jpeg"), elapsed: 0) == 0)
    }

    @Test func aPretendConversionKeepsThePathAndTakesTheTargetsExtension() {
        let report = item("Report.docx")
        let pdfTarget = ConversionCatalog.targets(pathExtension: "docx", isDirectory: false)[0]
        #expect(
            ConversionBatch.pretendResult(of: report, target: pdfTarget)
                == .converted(url: URL(fileURLWithPath: "/x/Report.pdf"), isDirectory: false))
        let zip = item("Bundle.zip")
        let unzip = ConversionCatalog.targets(pathExtension: "zip", isDirectory: false)[0]
        #expect(
            ConversionBatch.pretendResult(of: zip, target: unzip)
                == .converted(url: URL(fileURLWithPath: "/x/Bundle"), isDirectory: true))
        #expect(
            ConversionBatch.pretendArchive(beside: report)
                == .converted(url: URL(fileURLWithPath: "/x/Archive.zip"), isDirectory: false))
    }

    @Test func theColumnSaysWhatIsConverting() {
        #expect(ConversionBatch.progressText(label: "PDF", files: 1) == "Converting to PDF…")
        #expect(ConversionBatch.progressText(label: "PDF", files: 3) == "Converting 3 files to PDF…")
    }
}
