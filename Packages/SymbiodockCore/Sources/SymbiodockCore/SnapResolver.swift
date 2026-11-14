import CoreGraphics

/// Decides where the island settles when the user lets go of it.
public enum SnapResolver {
    /// Release within this distance (pt) of the notch center returns the island to the notch.
    public static let notchCaptureRadius: CGFloat = 120
    /// Release within this distance (pt) of a visible-frame corner pins the island there.
    public static let cornerCaptureRadius: CGFloat = 80

    /// Where the island settles when it is released at `point` (panel-local coordinates).
    public static func anchor(
        forRelease point: CGPoint, notch: CGRect, visibleFrame: CGRect
    ) -> IslandAnchor {
        guard point.x.isFinite, point.y.isFinite, !visibleFrame.isNull, !visibleFrame.isInfinite
        else { return .notch }
        // The notch capture uses the raw point: it is a distance, so it needs no clamping.
        if distance(point, CGPoint(x: notch.midX, y: notch.midY)) <= notchCaptureRadius {
            return .notch
        }
        // A release outside the visible frame counts as on its nearest border.
        let point = CGPoint(
            x: min(max(point.x, visibleFrame.minX), visibleFrame.maxX),
            y: min(max(point.y, visibleFrame.minY), visibleFrame.maxY))

        let corners: [(ScreenCorner, CGPoint)] = [
            (.topLeft, CGPoint(x: visibleFrame.minX, y: visibleFrame.minY)),
            (.topRight, CGPoint(x: visibleFrame.maxX, y: visibleFrame.minY)),
            (.bottomLeft, CGPoint(x: visibleFrame.minX, y: visibleFrame.maxY)),
            (.bottomRight, CGPoint(x: visibleFrame.maxX, y: visibleFrame.maxY)),
        ]
        let nearestCorner = corners
            .map { (corner: $0.0, distance: distance(point, $0.1)) }
            .filter { $0.distance <= cornerCaptureRadius }
            .min { $0.distance < $1.distance }
        if let nearestCorner { return .corner(nearestCorner.corner) }

        // Declared in tie-break order; the loop below keeps the first of equal distances.
        let edges: [(ScreenEdge, CGFloat)] = [
            (.top, abs(point.y - visibleFrame.minY)),
            (.bottom, abs(point.y - visibleFrame.maxY)),
            (.left, abs(point.x - visibleFrame.minX)),
            (.right, abs(point.x - visibleFrame.maxX)),
        ]
        var nearest = edges[0]
        for candidate in edges.dropFirst() where candidate.1 < nearest.1 { nearest = candidate }

        let along: CGFloat
        switch nearest.0 {
        case .top, .bottom:
            along = visibleFrame.width > 0 ? (point.x - visibleFrame.minX) / visibleFrame.width : 0.5
        case .left, .right:
            along = visibleFrame.height > 0 ? (point.y - visibleFrame.minY) / visibleFrame.height : 0.5
        }
        return .edge(nearest.0, fraction: Double(min(max(along, 0), 1)))
    }

    /// Where the island settles when it is released while its strands hold `surface`: on that
    /// surface, whichever edge is nearer. With no hold it is the plain nearest-place rule.
    /// The notch's capture radius outranks a held edge: `ReachResolver` hands the island to
    /// the notch there anyway, and a release must not depend on whether that has happened yet.
    public static func anchor(
        forRelease point: CGPoint, attachedTo surface: IslandSurface?, notch: CGRect,
        visibleFrame: CGRect
    ) -> IslandAnchor {
        guard let surface else {
            return anchor(forRelease: point, notch: notch, visibleFrame: visibleFrame)
        }
        guard case .edge(let edge) = surface else { return .notch }
        guard point.x.isFinite, point.y.isFinite, !visibleFrame.isNull, !visibleFrame.isInfinite
        else { return .notch }
        if distance(point, CGPoint(x: notch.midX, y: notch.midY)) <= notchCaptureRadius {
            return .notch
        }

        let x = min(max(point.x, visibleFrame.minX), visibleFrame.maxX)
        let y = min(max(point.y, visibleFrame.minY), visibleFrame.maxY)
        // Only how far along the held edge counts: the island is pulled in against it.
        let ends: [(ScreenCorner, CGFloat)]
        let along: CGFloat
        switch edge {
        case .top, .bottom:
            let (left, right): (ScreenCorner, ScreenCorner) =
                edge == .top ? (.topLeft, .topRight) : (.bottomLeft, .bottomRight)
            ends = [(left, x - visibleFrame.minX), (right, visibleFrame.maxX - x)]
            along = visibleFrame.width > 0 ? (x - visibleFrame.minX) / visibleFrame.width : 0.5
        case .left, .right:
            let (top, bottom): (ScreenCorner, ScreenCorner) =
                edge == .left ? (.topLeft, .bottomLeft) : (.topRight, .bottomRight)
            ends = [(top, y - visibleFrame.minY), (bottom, visibleFrame.maxY - y)]
            along = visibleFrame.height > 0 ? (y - visibleFrame.minY) / visibleFrame.height : 0.5
        }
        if let corner = ends.filter({ $0.1 <= cornerCaptureRadius }).min(by: { $0.1 < $1.1 }) {
            return .corner(corner.0)
        }
        return .edge(edge, fraction: Double(min(max(along, 0), 1)))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
