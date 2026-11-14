import CoreGraphics

/// Island frames in panel-local coordinates.
public enum IslandLayout {
    public static let expandedSize = CGSize(width: 360, height: 150)
    public static let hitPadding: CGFloat = 4
    /// Width added on each side of the notch while a track is shown collapsed.
    public static let collapsedWingWidth: CGFloat = 36

    public static func frame(
        phase: IslandPhase, notch: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect {
        switch phase {
        case .collapsed, .stretching, .detached, .settling:
            guard hasTrack else { return notch }
            return anchored(
                width: notch.width + 2 * collapsedWingWidth, height: notch.height,
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
        phase: IslandPhase, notch: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect {
        frame(phase: phase, notch: notch, screenSize: screenSize, hasTrack: hasTrack)
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
    /// Gap (pt) between a floating island and the edge of the visible frame.
    public static let floatingInset: CGFloat = 8

    /// The island frame for any anchor, in panel-local coordinates.
    public static func frame(
        anchor: IslandAnchor, phase: IslandPhase, notch: CGRect,
        visibleFrame: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect {
        // Every phase other than `.expanded` is laid out as collapsed.
        let isExpanded = phase == .expanded

        if anchor == .notch {
            return frame(
                phase: isExpanded ? .expanded : .collapsed, notch: notch,
                screenSize: screenSize, hasTrack: hasTrack)
        }

        let size = isExpanded ? expandedSize : floatingCollapsedSize
        let visible = usableBase(visibleFrame, screenSize: screenSize)
        var usable = visible.insetBy(dx: floatingInset, dy: floatingInset)
        // Too small for the inset: use the whole visible frame rather than an empty area.
        if usable.isNull || usable.width <= 0 || usable.height <= 0 { usable = visible }
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
        var rect = CGRect(origin: origin, size: size)
        // With the menu bar hidden the visible frame reaches the top of the display, and an
        // island docked there could end up behind the camera housing. Hang it below instead.
        if rect.intersects(notch) {
            rect.origin.y = notch.maxY + floatingInset
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
        visibleFrame: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect {
        frame(
            anchor: anchor, phase: phase, notch: notch, visibleFrame: visibleFrame,
            screenSize: screenSize, hasTrack: hasTrack)
            .insetBy(dx: -hitPadding, dy: -hitPadding)
    }
}
