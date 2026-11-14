import CoreGraphics

/// Something the island can take hold of while it is carried: the notch or a screen edge.
public enum IslandSurface: Equatable, Sendable {
    case notch
    case edge(ScreenEdge)
}

/// A surface close enough for the island's strands to reach, and where they take hold of it.
public struct ReachTarget: Equatable, Sendable {
    public var surface: IslandSurface
    /// Where the strands take hold of the surface (panel-local).
    public var root: CGPoint
    /// Unit vector along the surface, pointing the way `SymbioteSimulation` spreads its strands
    /// across an island that faces the surface squarely. Spreading the hold the same way keeps
    /// the strands from crossing, also when the island starts out pressed against the surface.
    public var tangent: CGPoint
    /// Half the length of surface the strands spread over.
    public var halfSpan: CGFloat
    /// From the hold to where the strands leave the island.
    public var distance: CGFloat

    public init(
        surface: IslandSurface, root: CGPoint, tangent: CGPoint, halfSpan: CGFloat, distance: CGFloat
    ) {
        self.surface = surface
        self.root = root
        self.tangent = tangent
        self.halfSpan = halfSpan
        self.distance = distance
    }
}

/// Decides which surface a carried island reaches for.
public enum ReachResolver {
    /// Strands shoot out once the island is this close (pt) to an edge.
    public static let edgeReach: CGFloat = 80
    /// Strands shoot out once the island is this close (pt) to the notch.
    public static let notchReach: CGFloat = 88
    /// Distance (pt) from its hold at which the thickest strand to an edge gives way.
    /// Thin strands go at 67 % of this, which must stay above `edgeReach`.
    public static let edgeTearDistance: CGFloat = 130
    /// The same for the notch; 67 % of it must stay above `notchReach`.
    public static let notchTearDistance: CGFloat = 140

    /// Strands leave the island from this far inside the side that faces the surface.
    static let bodyInset: CGFloat = 12
    /// Half the length of edge that strands from the island's short end fan out over.
    static let sideHalfSpan: CGFloat = 30

    /// Where strands that reach for `surface` leave an island occupying `body`.
    ///
    /// An island pushed past an edge (over the menu bar or the Dock) counts as pressed against
    /// it: the point stops at the edge, so no strand is drawn back across the island.
    public static func islandPoint(
        body: CGRect, surface: IslandSurface, visibleFrame: CGRect
    ) -> CGPoint {
        let dx = max(body.width / 2 - bodyInset, 0)
        let dy = max(body.height / 2 - bodyInset, 0)
        switch surface {
        case .notch:
            return CGPoint(x: body.midX, y: body.midY - dy)
        case .edge(.top):
            return CGPoint(x: body.midX, y: max(body.midY - dy, visibleFrame.minY))
        case .edge(.bottom):
            return CGPoint(x: body.midX, y: min(body.midY + dy, visibleFrame.maxY))
        case .edge(.left):
            return CGPoint(x: max(body.midX - dx, visibleFrame.minX), y: body.midY)
        case .edge(.right):
            return CGPoint(x: min(body.midX + dx, visibleFrame.maxX), y: body.midY)
        }
    }

    /// The surface within reach of an island occupying `body`, or nil when it is out in the open.
    /// The notch wins over the edge beside it; among edges the one nearest the island's side wins.
    /// - Parameter notchIsPhysical: false where the notch is only a place at the top of the display.
    public static func target(
        body: CGRect, notch: CGRect, notchIsPhysical: Bool, visibleFrame: CGRect
    ) -> ReachTarget? {
        guard isUsable(body), isUsable(notch), isUsable(visibleFrame) else { return nil }

        // Real hardware is held just inside its lower side; a stand-in notch is not drawn while
        // the island is away, so there the strands take hold of the display's top edge.
        let notchRoot = CGPoint(
            x: notch.midX, y: notchIsPhysical ? max(notch.maxY - 4, notch.minY) : notch.minY)
        let toNotch = distance(
            notchRoot, islandPoint(body: body, surface: .notch, visibleFrame: visibleFrame))
        if toNotch < notchReach {
            return ReachTarget(
                surface: .notch, root: notchRoot, tangent: CGPoint(x: -1, y: 0),
                halfSpan: notch.width * 0.33, distance: toNotch)
        }

        // Declared in tie-break order; the loop keeps the first of equal distances.
        var nearest: (edge: ScreenEdge, distance: CGFloat)?
        for edge in [ScreenEdge.top, .bottom, .left, .right] {
            let point = islandPoint(body: body, surface: .edge(edge), visibleFrame: visibleFrame)
            let gap: CGFloat
            switch edge {
            case .top: gap = abs(point.y - visibleFrame.minY)
            case .bottom: gap = abs(point.y - visibleFrame.maxY)
            case .left: gap = abs(point.x - visibleFrame.minX)
            case .right: gap = abs(point.x - visibleFrame.maxX)
            }
            if nearest == nil || gap < nearest!.distance { nearest = (edge, gap) }
        }
        guard let nearest, nearest.distance < edgeReach else { return nil }

        let point = islandPoint(
            body: body, surface: .edge(nearest.edge), visibleFrame: visibleFrame)
        switch nearest.edge {
        case .top, .bottom:
            // Never wider than the edge itself, and never past its corners.
            let halfSpan = min(body.width * 0.4, visibleFrame.width / 2)
            let x = min(max(point.x, visibleFrame.minX + halfSpan), visibleFrame.maxX - halfSpan)
            let y = nearest.edge == .top ? visibleFrame.minY : visibleFrame.maxY
            return ReachTarget(
                surface: .edge(nearest.edge), root: CGPoint(x: x, y: y),
                tangent: CGPoint(x: nearest.edge == .top ? -1 : 1, y: 0),
                halfSpan: halfSpan, distance: nearest.distance)
        case .left, .right:
            let halfSpan = min(sideHalfSpan, visibleFrame.height / 2)
            let y = min(max(point.y, visibleFrame.minY + halfSpan), visibleFrame.maxY - halfSpan)
            let x = nearest.edge == .left ? visibleFrame.minX : visibleFrame.maxX
            return ReachTarget(
                surface: .edge(nearest.edge), root: CGPoint(x: x, y: y),
                tangent: CGPoint(x: 0, y: nearest.edge == .left ? 1 : -1),
                halfSpan: halfSpan, distance: nearest.distance)
        }
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
