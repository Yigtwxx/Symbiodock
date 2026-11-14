import AppKit
import SwiftUI
import SymbiodockCore

/// Owns the overlay panel and keeps it matched to the island's display.
@MainActor
final class OverlayController {
    private let state = IslandState()
    private var panel: OverlayPanel?
    private var metrics: ScreenMetrics?
    private var notch: CGRect = .zero
    private var screenObserver: NSObjectProtocol?

    func start() {
        rebuildPanel()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanel() }
        }
    }

    /// Recreates the panel for the current display configuration.
    private func rebuildPanel() {
        panel?.close()
        panel = nil

        guard let screen = NSScreen.islandScreen else { return }
        let metrics = ScreenMetrics(screen: screen)
        let notch = NotchGeometry.notchRect(for: metrics)
        self.metrics = metrics
        self.notch = notch

        let panel = OverlayPanel(screenFrame: metrics.frame)
        let hostingView = NSHostingView(rootView: IslandView(state: state, notch: notch))
        // Keep SwiftUI from resizing the panel to the content's ideal size.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(metrics.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
