import CoreGraphics

public enum NotchGeometry {
    /// Size of the stand-in notch on displays that do not have one.
    public static let virtualNotchSize = CGSize(width: 200, height: 32)

    /// The notch rect in panel-local coordinates.
    public static func notchRect(for metrics: ScreenMetrics) -> CGRect {
        if metrics.hasNotch,
           let left = metrics.auxiliaryTopLeftWidth,
           let right = metrics.auxiliaryTopRightWidth {
            return CGRect(
                x: left,
                y: 0,
                width: metrics.frame.width - left - right,
                height: metrics.safeAreaTop)
        }
        return CGRect(
            x: (metrics.frame.width - virtualNotchSize.width) / 2,
            y: 0,
            width: virtualNotchSize.width,
            height: virtualNotchSize.height)
    }
}
