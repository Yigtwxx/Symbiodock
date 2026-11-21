import AppKit
import SymbiodockCore

/// Asks the system where the Dock's bar is. No permission is needed. The call is private
/// (HIServices `CoreDockGetRect`), so it is looked up at run time; where it is missing the
/// Dock counts as covering its whole edge (`DockGeometry.obstacle`).
@MainActor
enum DockProbe {
    private typealias GetRect = @convention(c) (UnsafeMutablePointer<CGRect>) -> Void

    private static let getRect: GetRect? = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "CoreDockGetRect")
        else { return nil }
        return unsafeBitCast(symbol, to: GetRect.self)
    }()

    /// The Dock's bar in the panel-local coordinates of the display `metrics` describes.
    /// It may lie on another display; the caller checks.
    static func rect(for metrics: ScreenMetrics) -> CGRect? {
        guard let getRect, let primary = NSScreen.screens.first else { return nil }
        var rect = CGRect.null
        getRect(&rect)
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0 else { return nil }
        // Reported from the primary display's top-left corner, y down.
        let global = CGRect(
            x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        return metrics.localRect(fromGlobal: global)
    }
}
