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
        if distance(point, CGPoint(x: notch.midX, y: notch.midY)) <= notchCaptureRadius {
            return .notch
        }

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

        // Declared in tie-break order; `min` keeps the first of equal distances.
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
        case .top, .bottom: along = (point.x - visibleFrame.minX) / visibleFrame.width
        case .left, .right: along = (point.y - visibleFrame.minY) / visibleFrame.height
        }
        return .edge(nearest.0, fraction: Double(min(max(along, 0), 1)))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
