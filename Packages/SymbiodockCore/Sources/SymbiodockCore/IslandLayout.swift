import CoreGraphics

/// Island frames in panel-local coordinates.
public enum IslandLayout {
    public static let expandedSize = CGSize(width: 480, height: 134)
    public static let hitPadding: CGFloat = 4
    /// Width added on each side of the notch while a track is shown collapsed.
    public static let collapsedWingWidth: CGFloat = 36
    /// How far the island with its wings reaches below the notch. The camera housing hides
    /// whatever lies behind it; this strip is what shows of the island's lower edge there,
    /// so that a light running along its rim passes under the notch unbroken.
    public static let notchLip: CGFloat = 2

    public static func frame(
        phase: IslandPhase, notch: CGRect, screenSize: CGSize, showsWings: Bool
    ) -> CGRect {
        switch phase {
        case .collapsed, .stretching, .detached, .settling:
            guard showsWings else { return notch }
            return anchored(
                width: notch.width + 2 * collapsedWingWidth, height: notch.height + notchLip,
                notch: notch, screenSize: screenSize)
        case .expanded:
            return anchored(
                width: max(expandedSize.width, notch.width),
                height: max(expandedSize.height, notch.height),
                notch: notch, screenSize: screenSize)
        }
    }

    /// The area in which the pointer counts as hovering the island.
    public static func hitRect(
        phase: IslandPhase, notch: CGRect, screenSize: CGSize, showsWings: Bool
    ) -> CGRect {
        frame(phase: phase, notch: notch, screenSize: screenSize, showsWings: showsWings)
            .insetBy(dx: -hitPadding, dy: -hitPadding)
    }

    /// A rect of the given size hanging from the top edge, centered on the notch, kept on screen.
    private static func anchored(
        width: CGFloat, height: CGFloat, notch: CGRect, screenSize: CGSize
    ) -> CGRect {
        let maxX = max(screenSize.width - width, 0)
        let x = min(max(notch.midX - width / 2, 0), maxX)
        return CGRect(x: x, y: 0, width: width, height: height)
    }
}

extension IslandLayout {
    /// Size of the island when it is collapsed away from the notch.
    public static let floatingCollapsedSize = CGSize(width: 200, height: 36)
    /// Size of the island when it is collapsed against the left or right edge: a strip that
    /// lies along the edge instead of sticking out from it.
    public static let sideCollapsedSize = CGSize(width: 36, height: 170)
    /// Gap (pt) kept below the notch by an island that had to move out from under it.
    public static let notchClearance: CGFloat = 8
    /// Radius of the island's free corners while collapsed, the same as the notch's.
    public static let collapsedCornerRadius: CGFloat = 10
    /// Radius of the island's free corners while expanded.
    public static let expandedCornerRadius: CGFloat = 24

    /// The screen edges the resting island lies against.
    public static func dockedEdges(anchor: IslandAnchor) -> Set<ScreenEdge> {
        switch anchor {
        case .notch: [.top]
        case .edge(let edge, _): [edge]
        case .corner(.topLeft): [.top, .left]
        case .corner(.topRight): [.top, .right]
        case .corner(.bottomLeft): [.bottom, .left]
        case .corner(.bottomRight): [.bottom, .right]
        }
    }

    /// The island's outline at rest. Docked, it sits against the screen edge the way the
    /// notch does: the corners on that edge are square and only the free ones are rounded.
    public static func cornerRadii(anchor: IslandAnchor, radius: CGFloat) -> IslandCornerRadii {
        var radii = IslandCornerRadii(
            topLeading: radius, topTrailing: radius, bottomLeading: radius, bottomTrailing: radius)
        func square(_ edge: ScreenEdge) {
            switch edge {
            case .top: radii.topLeading = 0; radii.topTrailing = 0
            case .bottom: radii.bottomLeading = 0; radii.bottomTrailing = 0
            case .left: radii.topLeading = 0; radii.bottomLeading = 0
            case .right: radii.topTrailing = 0; radii.bottomTrailing = 0
            }
        }
        switch anchor {
        case .notch: square(.top)
        case .edge(let edge, _): square(edge)
        case .corner(.topLeft): square(.top); square(.left)
        case .corner(.topRight): square(.top); square(.right)
        case .corner(.bottomLeft): square(.bottom); square(.left)
        case .corner(.bottomRight): square(.bottom); square(.right)
        }
        return radii
    }

    /// Whether the island rests along the left or right edge. Corners count as lying on
    /// the top or bottom edge.
    public static func isSideDocked(_ anchor: IslandAnchor) -> Bool {
        if case .edge(let edge, _) = anchor { return edge == .left || edge == .right }
        return false
    }

    /// Size of the island at rest away from the notch.
    private static func dockedSize(at anchor: IslandAnchor, isExpanded: Bool) -> CGSize {
        let isSide = isSideDocked(anchor)
        guard isExpanded else { return isSide ? sideCollapsedSize : floatingCollapsedSize }
        // Opened from a strip it is at least as tall as the strip: if hovering the strip's
        // end left the pointer outside the open island, it would close and open forever.
        return isSide
            ? CGSize(
                width: expandedSize.width,
                height: max(expandedSize.height, sideCollapsedSize.height))
            : expandedSize
    }

    /// The island frame for any anchor, in panel-local coordinates.
    public static func frame(
        anchor: IslandAnchor, phase: IslandPhase, notch: CGRect,
        visibleFrame: CGRect, screenSize: CGSize, showsWings: Bool
    ) -> CGRect {
        // Every phase other than `.expanded` is laid out as collapsed.
        let isExpanded = phase == .expanded

        if anchor == .notch {
            return frame(
                phase: isExpanded ? .expanded : .collapsed, notch: notch,
                screenSize: screenSize, showsWings: showsWings)
        }

        // A docked island lies flush against the border of the visible frame.
        let visible = usableBase(visibleFrame, screenSize: screenSize)
        let usable = visible

        /// Where an island of `size` sits at this anchor, before the notch is considered.
        func place(_ size: CGSize) -> CGRect {
            let minX = usable.minX
            let minY = usable.minY
            // Never below the minimum, so a frame smaller than the island still gives a finite origin.
            let maxX = max(usable.maxX - size.width, minX)
            let maxY = max(usable.maxY - size.height, minY)

            let origin: CGPoint
            switch anchor {
            case .notch:
                origin = CGPoint(x: minX, y: minY)  // handled above
            case .edge(let edge, let fraction):
                let f = fraction.isFinite ? CGFloat(min(max(fraction, 0), 1)) : 0.5
                // The fraction is where the island's center sits along the visible frame's edge
                // (as `SnapResolver` measures it), so an island keeps its center when it expands.
                let alongX = min(max(visible.minX + f * visible.width - size.width / 2, minX), maxX)
                let alongY = min(max(visible.minY + f * visible.height - size.height / 2, minY), maxY)
                switch edge {
                case .top: origin = CGPoint(x: alongX, y: minY)
                case .bottom: origin = CGPoint(x: alongX, y: maxY)
                case .left: origin = CGPoint(x: minX, y: alongY)
                case .right: origin = CGPoint(x: maxX, y: alongY)
                }
            case .corner(let corner):
                switch corner {
                case .topLeft: origin = CGPoint(x: minX, y: minY)
                case .topRight: origin = CGPoint(x: maxX, y: minY)
                case .bottomLeft: origin = CGPoint(x: minX, y: maxY)
                case .bottomRight: origin = CGPoint(x: maxX, y: maxY)
                }
            }
            return CGRect(origin: origin, size: size)
        }

        let expanded = dockedSize(at: anchor, isExpanded: true)
        var rect = place(dockedSize(at: anchor, isExpanded: isExpanded))
        // With the menu bar hidden the visible frame reaches the top of the display, and an
        // island docked there could end up behind the camera housing. Hang it below instead.
        // Collapsed and expanded must agree: if only the wider, expanded island met the
        // notch, hovering would move the island out from under the pointer.
        if rect.intersects(notch) || place(expanded).intersects(notch) {
            rect.origin.y = max(rect.origin.y, notch.maxY + notchClearance)
        }
        return rect
    }

    /// `visibleFrame` if it is usable, otherwise the whole display.
    private static func usableBase(_ visibleFrame: CGRect, screenSize: CGSize) -> CGRect {
        let finite = visibleFrame.minX.isFinite && visibleFrame.minY.isFinite
            && visibleFrame.width.isFinite && visibleFrame.height.isFinite
        if visibleFrame.isNull || !finite { return CGRect(origin: .zero, size: screenSize) }
        return visibleFrame
    }

    /// The area in which the pointer counts as hovering the island: its frame grown by `hitPadding`.
    public static func hitRect(
        anchor: IslandAnchor, phase: IslandPhase, notch: CGRect,
        visibleFrame: CGRect, screenSize: CGSize, showsWings: Bool
    ) -> CGRect {
        frame(
            anchor: anchor, phase: phase, notch: notch, visibleFrame: visibleFrame,
            screenSize: screenSize, showsWings: showsWings)
            .insetBy(dx: -hitPadding, dy: -hitPadding)
    }
}

/// Corner radii of the island's outline, in panel-local terms: leading is the left side.
public struct IslandCornerRadii: Equatable, Sendable {
    public var topLeading: CGFloat
    public var topTrailing: CGFloat
    public var bottomLeading: CGFloat
    public var bottomTrailing: CGFloat

    public init(
        topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat
    ) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomLeading = bottomLeading
        self.bottomTrailing = bottomTrailing
    }
}
