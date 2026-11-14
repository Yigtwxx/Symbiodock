import CoreGraphics

/// Island frames in panel-local coordinates.
public enum IslandLayout {
    public static let expandedSize = CGSize(width: 360, height: 150)
    public static let hitPadding: CGFloat = 4

    public static func frame(phase: IslandPhase, notch: CGRect, screenSize: CGSize) -> CGRect {
        switch phase {
        case .collapsed:
            return notch
        case .expanded:
            let width = max(expandedSize.width, notch.width)
            let height = max(expandedSize.height, notch.height)
            let maxX = max(screenSize.width - width, 0)
            let x = min(max(notch.midX - width / 2, 0), maxX)
            return CGRect(x: x, y: 0, width: width, height: height)
        }
    }

    /// The area in which the pointer counts as hovering the island.
    public static func hitRect(phase: IslandPhase, notch: CGRect, screenSize: CGSize) -> CGRect {
        frame(phase: phase, notch: notch, screenSize: screenSize)
            .insetBy(dx: -hitPadding, dy: -hitPadding)
    }
}
