import AppKit
import SymbiodockCore

extension ScreenMetrics {
    init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width)
    }
}

extension NSScreen {
    /// The display the island lives on: one with a notch if present, otherwise the main display.
    static var islandScreen: NSScreen? {
        screens.first(where: { ScreenMetrics(screen: $0).hasNotch }) ?? main
    }
}
