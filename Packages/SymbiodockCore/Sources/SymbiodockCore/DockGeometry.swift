import CoreGraphics

/// The Dock as something the island makes room for: where its bar lies and on which edge.
public struct DockObstacle: Equatable, Sendable {
    /// The Dock's bar, in panel-local coordinates.
    public var rect: CGRect
    /// The display edge the Dock lies on; never `.top`.
    public var edge: ScreenEdge

    public init(rect: CGRect, edge: ScreenEdge) {
        self.rect = rect
        self.edge = edge
    }

    /// Whether the Dock runs along the x axis.
    var isHorizontal: Bool { edge == .bottom || edge == .top }
    /// The stretch of its edge the Dock covers.
    var extent: ClosedRange<CGFloat> {
        isHorizontal ? rect.minX...rect.maxX : rect.minY...rect.maxY
    }
}

/// Where the Dock is, and what is left of the display beside it.
public enum DockGeometry {
    /// The system keeps less than this (pt) free for a hidden Dock; that is not a Dock to rest on.
    public static let minimumThickness: CGFloat = 16

    /// The Dock on a display, or nil when it takes up no room there (hidden, or on another display).
    ///
    /// - Parameters:
    ///   - visibleFrame: the display area free of the menu bar and the Dock, panel-local. It
    ///     tells which edge the Dock is on and how thick it is.
    ///   - reported: the Dock's bar as the system reports it, panel-local. It tells how much
    ///     of the edge the Dock covers; without it the Dock counts as covering all of it.
    public static func obstacle(
        screenSize: CGSize, visibleFrame: CGRect, reported: CGRect?
    ) -> DockObstacle? {
        guard isUsable(visibleFrame), screenSize.width > 0, screenSize.height > 0 else { return nil }
        let insets: [(ScreenEdge, CGFloat)] = [
            (.bottom, screenSize.height - visibleFrame.maxY),
            (.left, visibleFrame.minX),
            (.right, screenSize.width - visibleFrame.maxX),
        ]
        guard let (edge, thickness) = insets.max(by: { $0.1 < $1.1 }),
              thickness >= minimumThickness
        else { return nil }

        var strip: CGRect
        switch edge {
        case .left:
            strip = CGRect(x: 0, y: 0, width: thickness, height: screenSize.height)
        case .right:
            strip = CGRect(
                x: screenSize.width - thickness, y: 0, width: thickness, height: screenSize.height)
        case .bottom, .top:
            strip = CGRect(
                x: 0, y: screenSize.height - thickness, width: screenSize.width, height: thickness)
        }
        if let reported, isUsable(reported), reported.intersects(strip) {
            let covered = reported.intersection(strip)
            if edge == .bottom {
                strip.origin.x = covered.minX
                strip.size.width = covered.width
            } else {
                strip.origin.y = covered.minY
                strip.size.height = covered.height
            }
        }
        return DockObstacle(rect: strip, edge: edge)
    }

    /// `display` without the band the Dock lies in: what an island resting on the Dock docks against.
    public static func trimmed(_ display: CGRect, by dock: DockObstacle) -> CGRect {
        var frame = display
        switch dock.edge {
        case .bottom, .top:
            frame.size.height = max(min(dock.rect.minY, display.maxY) - display.minY, 0)
        case .left:
            let minX = min(max(dock.rect.maxX, display.minX), display.maxX)
            frame.size.width = display.maxX - minX
            frame.origin.x = minX
        case .right:
            frame.size.width = max(min(dock.rect.minX, display.maxX) - display.minX, 0)
        }
        return frame
    }

    /// The frame an island centered at `center` docks against while it is carried: the whole
    /// display beside the Dock, and the display without the Dock's band over the Dock.
    public static func frame(
        forCenter center: CGPoint, display: CGRect, dock: DockObstacle?
    ) -> CGRect {
        guard let dock, center.x.isFinite, center.y.isFinite else { return display }
        let along = dock.isHorizontal ? center.x : center.y
        return dock.extent.contains(along) ? trimmed(display, by: dock) : display
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }
}
