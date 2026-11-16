import CoreGraphics
import Testing
@testable import SymbiodockCore

struct StackLayoutTests {
    @Test func aLoneFileIsOneCardFillingTheTile() {
        #expect(StackLayout.boxSize(count: 1) == CGSize(width: 64, height: 96))
        #expect(StackLayout.cards(count: 1) == [CGRect(x: 0, y: 0, width: 64, height: 96)])
        #expect(StackLayout.peek(count: 1) == 0)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 32, y: 5), CGPoint(x: 63, y: 95)] {
            #expect(StackLayout.hit(point, count: 1) == .body)
        }
        #expect(StackLayout.hit(CGPoint(x: 64, y: 10), count: 1) == nil)
        #expect(StackLayout.hit(CGPoint(x: 10, y: -1), count: 1) == nil)
    }

    @Test func aStackIsEightPointsTallerThanATile() {
        #expect(StackLayout.boxSize(count: 2) == CGSize(width: 64, height: 104))
        #expect(StackLayout.boxSize(count: 40) == CGSize(width: 64, height: 104))
    }

    @Test func threeFilesGiveThreeCardsWithSevenPointTabs() {
        #expect(StackLayout.peek(count: 3) == 7)
        #expect(
            StackLayout.cards(count: 3) == [
                CGRect(x: 0, y: 14, width: 64, height: 90),
                CGRect(x: 3, y: 7, width: 58, height: 97),
                CGRect(x: 6, y: 0, width: 52, height: 104),
            ])
    }

    @Test func nineFilesDrawEightCardsWithThreePointTabsAndTwentyOneOfOverhang() {
        #expect(StackLayout.peek(count: 9) == 3)
        let cards = StackLayout.cards(count: 9)
        #expect(cards.count == 8)
        #expect(cards[0] == CGRect(x: 0, y: 21, width: 64, height: 83))
        #expect(cards[7].minY == 0)
        // Each card behind starts one tab higher than the one in front of it.
        for i in 1..<8 { #expect(cards[i - 1].minY - cards[i].minY == 3) }
        // The narrowing stops at half the tile.
        #expect(cards[5] == CGRect(x: 15, y: 6, width: 34, height: 98))
        #expect(cards[6] == CGRect(x: 16, y: 3, width: 32, height: 101))
        #expect(cards[7] == CGRect(x: 16, y: 0, width: 32, height: 104))
    }

    @Test func peekIsTheOverhangSharedOutAndClamped() {
        #expect(StackLayout.peek(count: 2) == 7)
        #expect(StackLayout.peek(count: 4) == 7)
        #expect(StackLayout.peek(count: 5) == 5.25)
        #expect(StackLayout.peek(count: 8) == 3)
        #expect(StackLayout.peek(count: 100) == 3)
    }

    @Test func aPointInATabNamesThatFile() {
        // Three files: tabs are y 7..<14 (card 1) and y 0..<7 (card 2).
        #expect(StackLayout.hit(CGPoint(x: 30, y: 10), count: 3) == .file(1))
        #expect(StackLayout.hit(CGPoint(x: 30, y: 3), count: 3) == .file(2))
        #expect(StackLayout.hit(CGPoint(x: 3, y: 10), count: 3) == .file(1))
    }

    @Test func theTopTwelvePointsOfTheFrontCardNameTheFrontFileAlone() {
        #expect(StackLayout.hit(CGPoint(x: 30, y: 14), count: 3) == .file(0))
        #expect(StackLayout.hit(CGPoint(x: 30, y: 25.9), count: 3) == .file(0))
        #expect(StackLayout.hit(CGPoint(x: 30, y: 26), count: 3) == .body)
        #expect(StackLayout.hit(CGPoint(x: 30, y: 103), count: 3) == .body)
        #expect(StackLayout.hit(CGPoint(x: 63, y: 30), count: 3) == .body)
    }

    @Test func pointsOutsideEveryCardAreNothing() {
        #expect(StackLayout.hit(CGPoint(x: 30, y: -0.5), count: 3) == nil)
        // Beside the narrowed tabs, above the front card.
        #expect(StackLayout.hit(CGPoint(x: 1, y: 10), count: 3) == nil)
        #expect(StackLayout.hit(CGPoint(x: 62, y: 10), count: 3) == nil)
        #expect(StackLayout.hit(CGPoint(x: 2, y: 3), count: 3) == nil)
        #expect(StackLayout.hit(CGPoint(x: 30, y: 104), count: 3) == nil)
        #expect(StackLayout.hit(CGPoint(x: 64, y: 50), count: 3) == nil)
    }

    @Test func framesNeverLeaveTheBox() {
        for count in 1...20 {
            let box = CGRect(origin: .zero, size: StackLayout.boxSize(count: count))
            let cards = StackLayout.cards(count: count)
            #expect(cards.count == min(count, 1 + StackLayout.maxBehind))
            for card in cards { #expect(box.contains(card)) }
            #expect(cards.last?.minY == 0 || count == 1)
        }
    }
}
