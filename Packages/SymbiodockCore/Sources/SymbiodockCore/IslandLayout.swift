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
        case .collapsed:
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
        let usable = visibleFrame.insetBy(dx: floatingInset, dy: floatingInset)
        let minX = usable.minX
        let minY = usable.minY
        let maxX = usable.maxX - size.width
        let maxY = usable.maxY - size.height

        let origin: CGPoint
        switch anchor {
        case .notch:
            origin = CGPoint(x: minX, y: minY)  // handled above
        case .edge(let edge, let fraction):
            let f = CGFloat(min(max(fraction, 0), 1))
            let alongX = minX + f * (usable.width - size.width)
            let alongY = minY + f * (usable.height - size.height)
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
