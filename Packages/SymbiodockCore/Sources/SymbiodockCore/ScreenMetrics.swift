import CoreGraphics

/// The facts about a display that the island needs, as plain values.
public struct ScreenMetrics: Equatable, Sendable {
    /// Display frame in AppKit global coordinates (origin bottom-left, y up).
    public var frame: CGRect
    /// Height of the top safe-area inset; greater than zero on notch displays.
    public var safeAreaTop: CGFloat
    /// Width of the usable area left of the notch, nil without a notch.
    public var auxiliaryTopLeftWidth: CGFloat?
    /// Width of the usable area right of the notch, nil without a notch.
    public var auxiliaryTopRightWidth: CGFloat?

    public init(
        frame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeftWidth = auxiliaryTopLeftWidth
        self.auxiliaryTopRightWidth = auxiliaryTopRightWidth
    }

    public var hasNotch: Bool {
        safeAreaTop > 0 && auxiliaryTopLeftWidth != nil && auxiliaryTopRightWidth != nil
    }

    /// Converts an AppKit global point to panel-local coordinates
    /// (origin top-left of this display, y down).
    public func localPoint(fromGlobal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }
}
