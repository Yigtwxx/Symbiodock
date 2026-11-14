import CoreGraphics

/// The facts about a display that the island needs, as plain values.
public struct ScreenMetrics: Equatable, Sendable {
    /// Display frame in AppKit global coordinates (origin bottom-left, y up).
    public var frame: CGRect
    /// Display area free of the menu bar and the system Dock, in AppKit global coordinates.
    public var visibleFrame: CGRect
    /// Height of the top safe-area inset; greater than zero on notch displays.
    public var safeAreaTop: CGFloat
    /// Width of the usable area left of the notch, nil without a notch.
    public var auxiliaryTopLeftWidth: CGFloat?
    /// Width of the usable area right of the notch, nil without a notch.
    public var auxiliaryTopRightWidth: CGFloat?

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
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

    /// Converts an AppKit global rect to panel-local coordinates
    /// (origin top-left of this display, y down).
    public func localRect(fromGlobal rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - frame.minX, y: frame.maxY - rect.maxY,
            width: rect.width, height: rect.height)
    }

    /// `visibleFrame` in panel-local coordinates.
    public var localVisibleFrame: CGRect { localRect(fromGlobal: visibleFrame) }
}
