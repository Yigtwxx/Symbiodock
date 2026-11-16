import CoreGraphics
import Foundation

/// The geometry of a drawer of files, in points in the stack's own box with the origin at the
/// top-left (SwiftUI's orientation). A lone file is a tile; a stack is a little taller so the
/// tabs of the cards behind it show above the front card.
public enum StackLayout {
    /// A lone file.
    public static let tile = CGSize(width: 64, height: 96)
    /// A stack's box is this much taller than a tile, bottom-aligned.
    public static let rise: CGFloat = 8
    /// Bounds of one tab, and of all of them together.
    public static let maxPeek: CGFloat = 7, minPeek: CGFloat = 3, maxOverhang: CGFloat = 21
    /// Cards drawn behind the front one; more files are counted but not drawn.
    public static let maxBehind = 7
    /// Each card behind is this much narrower on both sides.
    public static let narrowing: CGFloat = 3
    /// The top strip of the front card that names the front file alone.
    public static let grip: CGFloat = 12
    /// How far a hovered tab rises, and the whole stack under a pointer on its body.
    public static let lift: CGFloat = 6, bodyLift: CGFloat = 3

    /// The box of a stack of `count` files: the tile, or the tile plus the rise.
    public static func boxSize(count: Int) -> CGSize {
        count > 1 ? CGSize(width: tile.width, height: tile.height + rise) : tile
    }

    /// How much of each card behind shows above the one in front of it.
    public static func peek(count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let behind = CGFloat(min(count - 1, maxBehind))
        return max(minPeek, min(maxPeek, maxOverhang / behind))
    }

    /// Card frames in the box, front first; at most `1 + maxBehind` of them. A card behind
    /// reaches the box's bottom (the cards in front hide it) and never gets narrower than
    /// half the tile.
    public static func cards(count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let box = boxSize(count: count)
        let behind = min(count - 1, maxBehind)
        let peek = peek(count: count)
        let frontTop = peek * CGFloat(behind)
        var cards = [CGRect(x: 0, y: frontTop, width: box.width, height: box.height - frontTop)]
        for i in stride(from: 1, through: behind, by: 1) {
            let top = frontTop - peek * CGFloat(i)
            let inset = min(narrowing * CGFloat(i), tile.width / 4)
            cards.append(
                CGRect(x: inset, y: top, width: box.width - 2 * inset, height: box.height - top))
        }
        return cards
    }

    /// What a point in the box lands on: a file alone (a tab or the front card's grip) or the
    /// stack's body.
    public enum Hit: Equatable, Sendable { case file(Int), body }

    /// Front first. Nil outside every card; a lone tile is all body.
    public static func hit(_ point: CGPoint, count: Int) -> Hit? {
        let cards = cards(count: count)
        guard let front = cards.first else { return nil }
        if front.contains(point) {
            return count > 1 && point.y < front.minY + grip ? .file(0) : .body
        }
        return cards.indices.dropFirst().first { cards[$0].contains(point) }.map(Hit.file)
    }
}

/// What the pointer rests on in the shelf: a stack and where on it.
public struct ShelfHover: Equatable, Sendable {
    public var stack: UUID
    public var hit: StackLayout.Hit
    public init(stack: UUID, hit: StackLayout.Hit) {
        self.stack = stack
        self.hit = hit
    }
}
