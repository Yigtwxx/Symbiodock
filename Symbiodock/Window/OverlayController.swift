import AppKit
import SwiftUI
import SymbiodockCore

/// Owns the overlay panel, keeps it matched to the island's display,
/// and turns pointer movement into hover state and click-through.
@MainActor
final class OverlayController {
    /// Switch to `.polling` if event monitors do not deliver pointer movement.
    private static let trackerMode: MouseTracker.Mode = .eventMonitors

    private let state = IslandState()
    private var panel: OverlayPanel?
    private var metrics: ScreenMetrics?
    private var notch: CGRect = .zero
    private var screenObserver: NSObjectProtocol?
    private var tracker: MouseTracker?
    private var pointerInside = false
    private var hoverTask: Task<Void, Never>?

    func start() {
        rebuildPanel()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanel() }
        }

        let tracker = MouseTracker(mode: Self.trackerMode) { [weak self] point in
            self?.pointerMoved(toGlobal: point)
        }
        tracker.start()
        self.tracker = tracker
    }

    /// Recreates the panel for the current display configuration.
    private func rebuildPanel() {
        panel?.close()
        panel = nil
        pointerInside = false

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

    private func pointerMoved(toGlobal point: CGPoint) {
        guard let metrics, let panel else { return }

        let hitRect = IslandLayout.hitRect(
            phase: state.phase, notch: notch, screenSize: metrics.frame.size)
        let inside = hitRect.contains(metrics.localPoint(fromGlobal: point))

        // Clicks reach the panel only while the pointer is on the island.
        panel.ignoresMouseEvents = !inside

        guard inside != pointerInside else { return }
        pointerInside = inside

        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: inside ? HoverTiming.enterDelay : HoverTiming.exitDelay)
            guard !Task.isCancelled else { return }
            self?.state.setHovering(inside)
        }
    }
}
