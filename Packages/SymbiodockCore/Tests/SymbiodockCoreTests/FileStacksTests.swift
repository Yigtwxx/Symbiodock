import Foundation
import Testing
@testable import SymbiodockCore

struct FileStacksTests {
    private func item(_ name: String) -> ShelfItem {
        ShelfItem(url: URL(fileURLWithPath: "/x/\(name)"), isDirectory: false)
    }

    /// The shelf as names, one array per stack, front first.
    private func shape(_ shelf: FileShelf) -> [[String]] {
        shelf.stacks.map { $0.items.map(\.name) }
    }

    /// Every stack is one run in `items`, and every item names the stack it lies in.
    private func isContiguous(_ shelf: FileShelf) -> Bool {
        var seen = Set<UUID>()
        var last: UUID?
        for item in shelf.items {
            if item.stack != last {
                guard seen.insert(item.stack).inserted else { return false }
                last = item.stack
            }
        }
        return shelf.stacks.flatMap(\.items) == shelf.items
    }

    private func selectionIsValid(_ shelf: FileShelf) -> Bool {
        let ids = Set(shelf.items.map(\.id))
        guard shelf.selection.isSubset(of: ids) else { return false }
        if let id = shelf.selectedID { return shelf.selection.contains(id) }
        return shelf.selection.isEmpty
    }

    private func shelf(_ names: [String]) -> FileShelf {
        var shelf = FileShelf()
        shelf.add(names.map(item))
        return shelf
    }

    // MARK: Forming stacks

    @Test func aLoneItemIsItsOwnStack() {
        let a = item("a.png")
        #expect(a.stack == a.id)
        let b = ShelfItem(url: a.url, isDirectory: false, stack: nil)
        #expect(b.stack == b.id)
    }

    @Test func droppingThreeAtOnceMakesOneStackAllSelectedFirstInFront() {
        var shelf = FileShelf()
        let new = UUID()
        shelf.add(["a.png", "b.png", "c.png"].map(item), newStack: new)
        #expect(shape(shelf) == [["a.png", "b.png", "c.png"]])
        #expect(shelf.stacks[0].id == new)
        #expect(shelf.stacks[0].front.name == "a.png")
        #expect(shelf.items.allSatisfy { $0.stack == new })
        #expect(shelf.selection == Set(shelf.items.map(\.id)))
        #expect(shelf.selectedID == shelf.items[2].id)
        #expect(isContiguous(shelf))
    }

    @Test func droppingOneMakesALoneTileInFront() {
        var shelf = shelf(["a.png", "b.png"])
        let c = item("c.png")
        shelf.add([c])
        #expect(shape(shelf) == [["c.png"], ["a.png", "b.png"]])
        #expect(shelf.stacks[0].id == c.id)
        #expect(shelf.selection == [c.id])
        #expect(shelf.selectedID == c.id)
    }

    @Test func droppingOntoAStackJoinsItInFrontAndKeepsItsPlace() {
        var shelf = shelf(["a.png", "b.png"])
        shelf.add([item("z.png")])
        let target = shelf.stacks[1].id
        shelf.add([item("c.png"), item("d.png")], onto: target)
        #expect(shape(shelf) == [["z.png"], ["c.png", "d.png", "a.png", "b.png"]])
        #expect(shelf.stacks[1].id == target)
        #expect(shelf.selection.count == 2)
        #expect(shelf.selectedID == shelf.items[2].id)
        #expect(isContiguous(shelf))
    }

    @Test func droppingOntoAnUnknownStackFallsBackToANewOne() {
        var shelf = shelf(["a.png"])
        shelf.add([item("b.png")], onto: UUID())
        #expect(shape(shelf) == [["b.png"], ["a.png"]])
    }

    @Test func reDroppingAHeldFileOntoAnotherStackMovesItAndKeepsItsId() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let b = shelf.items[1]
        shelf.add([item("z.png")])
        let target = shelf.stacks[0].id
        shelf.add([item("b.png")], onto: target)
        #expect(shape(shelf) == [["b.png", "z.png"], ["a.png", "c.png"]])
        #expect(shelf.items[0].id == b.id)
        #expect(shelf.count == 4)
        #expect(shelf.selection == [b.id])
        #expect(isContiguous(shelf))
    }

    @Test func reDroppingHeldFilesWithoutATargetFormsOneNewStackInFront() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        shelf.add([item("z.png")])
        let left = shelf.stacks[1].id
        shelf.add([item("c.png"), item("a.png")])
        #expect(shape(shelf) == [["c.png", "a.png"], ["z.png"], ["b.png"]])
        #expect(shelf.stacks[2].id == left)
        #expect(isContiguous(shelf))
    }

    @Test func reDroppingOneHeldFileWithoutATargetMakesItALoneTileInFront() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let b = shelf.items[1]
        shelf.add([item("z.png")])
        shelf.add([item("b.png")])
        #expect(shape(shelf) == [["b.png"], ["z.png"], ["a.png", "c.png"]])
        #expect(shelf.stacks[0].id == b.id)
        #expect(shelf.items[0].id == b.id)
    }

    @Test func reDroppingTheOnlyFileOfAStackOntoItselfChangesNothingButTheSelection() {
        var shelf = shelf(["a.png"])
        shelf.add([item("z.png")])
        let target = shelf.stacks[1].id
        shelf.add([item("a.png")], onto: target)
        #expect(shape(shelf) == [["z.png"], ["a.png"]])
        #expect(shelf.stacks[1].id == target)
    }

    // MARK: One drop arriving piece by piece

    @Test func filesArrivingIntoANewStackMakeItInFrontThenJoinBehindInOrder() {
        var shelf = shelf(["a.png", "b.png"])
        let drop = UUID()
        let (c, d, e) = (item("c.png"), item("d.png"), item("e.png"))
        shelf.add([c], into: drop)
        #expect(shape(shelf) == [["c.png"], ["a.png", "b.png"]])
        #expect(shelf.stacks[0].id == drop)
        #expect(shelf.selection == [c.id])
        shelf.add([d], into: drop)
        shelf.add([e], into: drop)
        #expect(shape(shelf) == [["c.png", "d.png", "e.png"], ["a.png", "b.png"]])
        #expect(shelf.stacks[0].id == drop)
        #expect(shelf.selection == [c.id, d.id, e.id])
        #expect(shelf.selectedID == e.id)
        #expect(isContiguous(shelf))
    }

    @Test func oneFileArrivingIntoANewStackIsALoneTile() {
        var shelf = shelf(["a.png"])
        let drop = UUID()
        shelf.add([item("b.png")], into: drop)
        #expect(shape(shelf) == [["b.png"], ["a.png"]])
        #expect(shelf.stack(drop)?.items.count == 1)
    }

    @Test func severalArrivingAtOnceIntoANewStackKeepTheirOrder() {
        var shelf = FileShelf()
        let drop = UUID()
        shelf.add(["a.png", "b.png", "c.png"].map(item), into: drop)
        #expect(shape(shelf) == [["a.png", "b.png", "c.png"]])
        #expect(shelf.stacks[0].id == drop)
        #expect(shelf.selection == Set(shelf.items.map(\.id)))
    }

    @Test func aHeldFileArrivingIntoTheDropsStackMovesThereAndKeepsItsId() {
        var shelf = shelf(["a.png", "b.png"])
        let b = shelf.items[1]
        let drop = UUID()
        shelf.add([item("c.png")], into: drop)
        shelf.add([item("b.png")], into: drop)
        #expect(shape(shelf) == [["c.png", "b.png"], ["a.png"]])
        #expect(shelf.items[1].id == b.id)
        #expect(shelf.count == 3)
        #expect(isContiguous(shelf))
        #expect(selectionIsValid(shelf))
    }

    // MARK: Moving

    @Test func movingATileOntoAnotherPutsItInFrontAndSelectsIt() {
        var shelf = FileShelf()
        shelf.add([item("a.png")])
        shelf.add([item("b.png")])
        shelf.add([item("c.png")])
        let (c, b, a) = (shelf.items[0], shelf.items[1], shelf.items[2])
        shelf.move([c.id], onto: a.stack)
        #expect(shape(shelf) == [["b.png"], ["c.png", "a.png"]])
        #expect(shelf.selection == [c.id])
        shelf.move([b.id], onto: a.stack)
        #expect(shape(shelf) == [["b.png", "c.png", "a.png"]])
        #expect(shelf.stacks[0].id == a.stack)
        #expect(shelf.selectedID == b.id)
        #expect(isContiguous(shelf))
    }

    @Test func movingSeveralKeepsTheirOrderInFront() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        shelf.add([item("z.png")])
        let ids = shelf.stacks[1].items.map(\.id)
        shelf.move([ids[2], ids[0]], onto: shelf.stacks[0].id)
        #expect(shape(shelf) == [["c.png", "a.png", "z.png"], ["b.png"]])
        #expect(shelf.selection == [ids[2], ids[0]])
        #expect(shelf.selectedID == ids[0])
        #expect(isContiguous(shelf))
    }

    @Test func movingFilesAlreadyInThatStackBringsThemToItsFront() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let ids = shelf.items.map(\.id)
        shelf.move([ids[2]], onto: shelf.stacks[0].id)
        #expect(shape(shelf) == [["c.png", "a.png", "b.png"]])
    }

    @Test func movingEveryFileOutOfAStackRemovesIt() {
        var shelf = shelf(["a.png", "b.png"])
        shelf.add([item("z.png")])
        let ids = shelf.stacks[1].items.map(\.id)
        let gone = shelf.stacks[1].id
        shelf.move(ids, onto: shelf.stacks[0].id)
        #expect(shape(shelf) == [["a.png", "b.png", "z.png"]])
        #expect(shelf.stack(gone) == nil)
    }

    @Test func movingOntoAnUnknownStackOrWithUnknownIdsChangesNothing() {
        var shelf = shelf(["a.png", "b.png"])
        shelf.add([item("z.png")])
        let before = shelf
        shelf.move([shelf.items[0].id], onto: UUID())
        #expect(shelf == before)
        shelf.move([UUID()], onto: shelf.stacks[0].id)
        #expect(shelf == before)
        shelf.move([], onto: shelf.stacks[0].id)
        #expect(shelf == before)
    }

    // MARK: Separating and ordering

    @Test func separatingAFileMakesItALoneTileRightAfterTheStackItLeft() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        shelf.add([item("z.png")])
        shelf.add([item("y.png")])
        let b = shelf.stacks[2].items[1]
        shelf.separate([b.id])
        #expect(shape(shelf) == [["y.png"], ["z.png"], ["a.png", "c.png"], ["b.png"]])
        #expect(shelf.stacks[3].id == b.id)
        #expect(shelf.items[4].stack == b.id)
        #expect(isContiguous(shelf))
    }

    @Test func separatingSeveralKeepsTheirOrderAndUsesTheGivenStackIds() {
        var shelf = shelf(["a.png", "b.png", "c.png", "d.png"])
        let ids = shelf.items.map(\.id)
        let (s1, s2) = (UUID(), UUID())
        shelf.separate([ids[3], ids[1]], newStacks: [s1, s2])
        #expect(shape(shelf) == [["a.png", "c.png"], ["d.png"], ["b.png"]])
        #expect(shelf.stacks.map(\.id).suffix(2) == [s1, s2])
        #expect(isContiguous(shelf))
    }

    @Test func separatingTheOnlyFileOfAStackChangesNothing() {
        var shelf = shelf(["a.png"])
        let before = shelf
        shelf.separate([shelf.items[0].id, UUID()])
        #expect(shelf == before)
    }

    @Test func separatingEveryFileOfAStackLeavesTheLastOneInIt() {
        var shelf = shelf(["a.png", "b.png"])
        let ids = shelf.items.map(\.id)
        shelf.separate(ids)
        // "a" leaves; "b" is then the stack's only file and stays where it is.
        #expect(shape(shelf) == [["b.png"], ["a.png"]])
        #expect(isContiguous(shelf))
    }

    @Test func aSeparatedFileNeverTakesAStackIdAnotherStackHolds() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let (a, b) = (shelf.items[0], shelf.items[1])
        shelf.separate([a.id])
        // The lone tile "a" is the stack named after it; "b" joins it in front.
        shelf.move([b.id], onto: a.id)
        #expect(shape(shelf) == [["c.png"], ["b.png", "a.png"]])
        #expect(shelf.stacks[1].id == a.id)
        // "a" leaves; its own id is still a stack's, so it gets a fresh one.
        shelf.separate([a.id])
        #expect(shape(shelf) == [["c.png"], ["b.png"], ["a.png"]])
        #expect(shelf.stacks[1].id == a.id)
        #expect(shelf.stacks[2].id != a.id)
        #expect(isContiguous(shelf))
    }

    @Test func bringingAFileToFrontReordersOnlyItsStack() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        shelf.add([item("z.png")])
        let c = shelf.stacks[1].items[2]
        shelf.bringToFront(c.id)
        #expect(shape(shelf) == [["z.png"], ["c.png", "a.png", "b.png"]])
        let before = shelf
        shelf.bringToFront(c.id)
        shelf.bringToFront(UUID())
        #expect(shelf == before)
    }

    // MARK: Selection

    @Test func selectingTakesExactlyTheseAndDropsUnknownIds() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let ids = shelf.items.map(\.id)
        shelf.select([ids[0], ids[2], UUID()])
        #expect(shelf.selection == [ids[0], ids[2]])
        #expect(shelf.selectedID == ids[2])
        #expect(shelf.selectedItems.map(\.name) == ["a.png", "c.png"])
        shelf.select([UUID()])
        #expect(shelf.selection == [ids[0], ids[2]])
        shelf.select([ids[1]])
        #expect(shelf.selection == [ids[1]])
    }

    @Test func selectedItemsFollowShelfOrderNotCallOrder() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let ids = shelf.items.map(\.id)
        shelf.select([ids[2], ids[0]])
        #expect(shelf.selectedItems.map(\.name) == ["a.png", "c.png"])
        #expect(shelf.selectedID == ids[0])
    }

    @Test func togglingAddsThenRemovesButNeverEmptiesTheSelection() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let ids = shelf.items.map(\.id)
        shelf.select([ids[0]])
        shelf.toggle([ids[1]])
        #expect(shelf.selection == [ids[0], ids[1]])
        #expect(shelf.selectedID == ids[1])
        shelf.toggle([ids[1]])
        #expect(shelf.selection == [ids[0]])
        #expect(shelf.selectedID == ids[0])
        shelf.toggle([ids[0]])
        #expect(shelf.selection == [ids[0]])
        shelf.toggle([ids[1], ids[2]])
        #expect(shelf.selection == Set(ids))
        #expect(shelf.selectedID == ids[2])
        shelf.toggle([ids[2], ids[1], UUID()])
        #expect(shelf.selection == [ids[0]])
        shelf.toggle([])
        shelf.toggle([UUID()])
        #expect(shelf.selection == [ids[0]])
        #expect(selectionIsValid(shelf))
    }

    @Test func togglingSomeSelectedAndSomeNotAddsAll() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let ids = shelf.items.map(\.id)
        shelf.select([ids[0]])
        shelf.toggle([ids[0], ids[1]])
        #expect(shelf.selection == [ids[0], ids[1]])
        #expect(shelf.selectedID == ids[1])
    }

    // MARK: Removing

    @Test func removingTheWholeSelectionPicksTheNeighbour() {
        var shelf = shelf(["a.png", "b.png", "c.png", "d.png"])
        let ids = shelf.items.map(\.id)
        shelf.select([ids[1], ids[2]])
        shelf.remove([ids[1], ids[2]])
        #expect(shelf.items.map(\.id) == [ids[0], ids[3]])
        #expect(shelf.selection == [ids[3]])
        #expect(shelf.selectedID == ids[3])
        shelf.select([ids[3]])
        shelf.remove([ids[3]])
        #expect(shelf.selection == [ids[0]])
        shelf.remove([ids[0]])
        #expect(shelf.selection.isEmpty)
        #expect(shelf.selectedID == nil)
    }

    @Test func removingPartOfTheSelectionKeepsTheRest() {
        var shelf = shelf(["a.png", "b.png", "c.png"])
        let ids = shelf.items.map(\.id)
        shelf.select([ids[0], ids[2]])
        shelf.remove([ids[2]])
        #expect(shelf.selection == [ids[0]])
        #expect(shelf.selectedID == ids[0])
        shelf.remove([ids[1], UUID()])
        #expect(shelf.selection == [ids[0]])
    }

    @Test func removingTheLastFileOfAStackRemovesTheStack() {
        var shelf = shelf(["a.png", "b.png"])
        shelf.add([item("z.png")])
        let gone = shelf.stacks[1].id
        shelf.remove(shelf.stacks[1].items.map(\.id))
        #expect(shape(shelf) == [["z.png"]])
        #expect(shelf.stack(gone) == nil)
    }

    // MARK: Lookup and the rest

    @Test func stacksCanBeFoundByIdAndByAFileTheyHold() {
        var shelf = shelf(["a.png", "b.png"])
        shelf.add([item("z.png")])
        let stack = shelf.stacks[1]
        #expect(shelf.stack(stack.id) == stack)
        #expect(shelf.stack(holding: stack.items[1].id) == stack)
        #expect(shelf.stack(UUID()) == nil)
        #expect(shelf.stack(holding: UUID()) == nil)
    }

    @Test func countAndBubbleKindsStillCountFilesNotStacks() {
        var shelf = FileShelf()
        shelf.add([item("a.png"), item("b.pdf"), item("c.jpg")])
        shelf.add([item("d.mov")])
        #expect(shelf.count == 4)
        #expect(shelf.stacks.count == 2)
        #expect(shelf.bubbleKinds == [.video, .image, .pdf])
    }

    @Test func everyOperationKeepsStacksContiguousAndTheSelectionValid() {
        var shelf = FileShelf()
        shelf.add(["a", "b", "c"].map { item("\($0).png") })
        shelf.add([item("d.png")])
        shelf.add([item("e.png"), item("f.png")])
        func check() {
            #expect(isContiguous(shelf))
            #expect(selectionIsValid(shelf))
        }
        check()
        shelf.move([shelf.items[0].id], onto: shelf.stacks[1].id)
        check()
        shelf.separate([shelf.items[2].id, shelf.items[3].id])
        check()
        shelf.bringToFront(shelf.items[3].id)
        check()
        shelf.toggle([shelf.items[1].id])
        check()
        shelf.add([item("a.png")], onto: shelf.stacks[0].id)
        check()
        let drop = UUID()
        shelf.add([item("g.png")], into: drop)
        shelf.add([item("b.png")], into: drop)
        check()
        shelf.replace(shelf.items[0].id, url: URL(fileURLWithPath: "/x/b.png"), isDirectory: false)
        check()
        shelf.remove(shelf.items.prefix(3).map(\.id))
        check()
        shelf.clear()
        check()
    }
}
