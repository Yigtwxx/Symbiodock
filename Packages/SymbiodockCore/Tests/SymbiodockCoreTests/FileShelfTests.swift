import Foundation
import Testing
@testable import SymbiodockCore

struct FileShelfTests {
    private func item(_ path: String, dir: Bool = false) -> ShelfItem {
        ShelfItem(url: URL(fileURLWithPath: path), isDirectory: dir)
    }

    @Test func addingToAnEmptyShelfKeepsOrderAndSelectsTheFirst() {
        let (a, b, c) = (item("/x/a.png"), item("/x/b.pdf"), item("/x/c.jpg"))
        var shelf = FileShelf()
        shelf.add([a, b, c])
        #expect(shelf.items == [a, b, c])
        #expect(shelf.selected == a)
    }

    @Test func laterItemsGoInFrontAndGetSelected() {
        let (a, b, c, d) = (item("/x/a.png"), item("/x/b.pdf"), item("/x/c.jpg"), item("/x/d.mov"))
        var shelf = FileShelf()
        shelf.add([a, b, c])
        shelf.add([d])
        #expect(shelf.items == [d, a, b, c])
        #expect(shelf.selected == d)
    }

    @Test func aHeldPathMovesToTheFrontWithItsId() {
        let (a, b) = (item("/x/a.png"), item("/x/b.pdf"))
        var shelf = FileShelf()
        shelf.add([a, b])
        shelf.add([item("/x/b.pdf"), item("/x/./a.png")])
        #expect(shelf.count == 2)
        #expect(shelf.items.map(\.id) == [b.id, a.id])
        #expect(shelf.selectedID == b.id)
        shelf.add([item("/x/./a.png")])
        #expect(shelf.count == 2)
        #expect(shelf.items[0].id == a.id)
    }

    @Test func removingTheSelectedMiddleItemSelectsTheNextOne() {
        let (a, b, c) = (item("/x/a.png"), item("/x/b.pdf"), item("/x/c.jpg"))
        var shelf = FileShelf(items: [a, b, c])
        shelf.select(b.id)
        shelf.remove(b.id)
        #expect(shelf.selectedID == c.id)
    }

    @Test func removingTheLastSelectsTheNewLastAndTheOnlyDeselects() {
        let (a, b) = (item("/x/a.png"), item("/x/b.pdf"))
        var shelf = FileShelf(items: [a, b])
        shelf.select(b.id)
        shelf.remove(b.id)
        #expect(shelf.selectedID == a.id)
        shelf.remove(a.id)
        #expect(shelf.selectedID == nil)
        #expect(shelf.isEmpty)
    }

    @Test func removingAnotherItemKeepsTheSelection() {
        let (a, b) = (item("/x/a.png"), item("/x/b.pdf"))
        var shelf = FileShelf(items: [a, b])
        shelf.remove(b.id)
        #expect(shelf.selectedID == a.id)
    }

    @Test func replaceKeepsIdIndexAndSelectionAndKindFollowsTheUrl() {
        let (a, b) = (item("/x/a.png"), item("/x/b.pdf"))
        var shelf = FileShelf(items: [a, b])
        shelf.select(b.id)
        shelf.replace(b.id, url: URL(fileURLWithPath: "/x/b.docx"), isDirectory: false)
        #expect(shelf.items[1].id == b.id)
        #expect(shelf.selectedID == b.id)
        #expect(shelf.items[1].kind == .document)
        #expect(shelf.items[1].badge == "DOCX")
    }

    @Test func selectingAnUnknownIdChangesNothing() {
        let a = item("/x/a.png")
        var shelf = FileShelf(items: [a])
        shelf.select(UUID())
        #expect(shelf.selectedID == a.id)
    }

    @Test func clearEmptiesAndDeselects() {
        var shelf = FileShelf(items: [item("/x/a.png")])
        shelf.clear()
        #expect(shelf.isEmpty)
        #expect(shelf.selectedID == nil)
        #expect(shelf.selected == nil)
    }

    @Test func bubbleKindsAreDistinctNewestFirstAndAtMostThree() {
        let shelf = FileShelf(items: [
            item("/x/a.png"), item("/x/b.pdf"), item("/x/c.jpg"), item("/x/d.docx"), item("/x/e.mov"),
        ])
        #expect(shelf.bubbleKinds == [.image, .pdf, .document])
    }

    @Test func badgesNameTheExtensionOrAStandIn() {
        #expect(item("/x/Report.docx").badge == "DOCX")
        #expect(item("/x/Site.webarchive").badge == "WEBAR")
        #expect(item("/x/Photos", dir: true).badge == "FOLDER")
        #expect(item("/x/Makefile").badge == "FILE")
        #expect(item("/x/Report.docx").name == "Report.docx")
    }
}
