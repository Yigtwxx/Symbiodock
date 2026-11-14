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
