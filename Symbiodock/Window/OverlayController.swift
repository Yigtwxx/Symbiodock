import AppKit
import SwiftUI
import SymbiodockCore

/// Owns the overlay panel, keeps it matched to the island's display,
/// and turns pointer movement into hover state and click-through.
@MainActor
final class OverlayController {
    /// Switch to `.polling` if event monitors do not deliver pointer movement.
    private static let trackerMode: MouseTracker.Mode = .eventMonitors

    private let state: IslandState
    private let contextMenu: NSMenu
    private var panel: OverlayPanel?
    private var metrics: ScreenMetrics?
    private var notch: CGRect = .zero
    private var screenObserver: NSObjectProtocol?
    private var tracker: MouseTracker?
    private var pointerInside = false
    private var hoverTask: Task<Void, Never>?

    init(state: IslandState, contextMenu: NSMenu) {
        self.state = state
        self.contextMenu = contextMenu
    }

    func start() {
        // The tracker must exist before the first rebuild: if the pointer is already on
        // the island at launch, the rebuild turns on the tracker's safety-net polling.
        let tracker = MouseTracker(mode: Self.trackerMode) { [weak self] point in
            self?.pointerMoved(toGlobal: point)
        }
        tracker.start()
        self.tracker = tracker

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
        guard let screen = NSScreen.islandScreen else {
            resetHoverState()
            panel?.close()
            panel = nil
            metrics = nil
            notch = .zero
            return
        }
        let metrics = ScreenMetrics(screen: screen)
        // Nothing changed (e.g. unrelated screen-parameter notification): keep the panel.
        if panel != nil, metrics == self.metrics { return }

        resetHoverState()
        panel?.close()
        panel = nil

        let notch = NotchGeometry.notchRect(for: metrics)
        self.metrics = metrics
        self.notch = notch

        let panel = OverlayPanel(screenFrame: metrics.frame)
        let hostingView = IslandHostingView(rootView: IslandView(state: state, notch: notch))
        hostingView.contextMenu = contextMenu
        // Keep SwiftUI from resizing the panel to the content's ideal size.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(metrics.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // The new panel ignores mouse events; re-check in case the pointer is already on the island.
        pointerMoved(toGlobal: NSEvent.mouseLocation)
    }

    /// Drops pending hover work and collapses the island so no stale state survives a rebuild.
    private func resetHoverState() {
        hoverTask?.cancel()
        hoverTask = nil
        state.setHovering(false)
        pointerInside = false
        tracker?.setSupplementalPolling(false)
    }

    /// Re-checks the pointer after something other than pointer movement changed the hit rect.
    func refreshPointer() {
        pointerMoved(toGlobal: NSEvent.mouseLocation)
    }

    private func pointerMoved(toGlobal point: CGPoint) {
        guard let metrics, let panel else { return }

        let hitRect = IslandLayout.hitRect(
            phase: state.phase, notch: notch, screenSize: metrics.frame.size,
            hasTrack: state.hasTrack)
        let inside = hitRect.contains(metrics.localPoint(fromGlobal: point))

        // Clicks reach the panel only while the pointer is on the island. Assign only on
        // change: this runs on every mouse move system-wide. While the panel accepts events
        // the global monitor is blind, so poll as a safety net against a lost exit event.
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
            tracker?.setSupplementalPolling(inside)
        }

        guard inside != pointerInside else { return }
        pointerInside = inside

        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: inside ? HoverTiming.enterDelay : HoverTiming.exitDelay)
            guard !Task.isCancelled, let self else { return }
            self.state.setHovering(inside)
            // The hit rect depends on the phase; re-check. This only schedules new work
            // when the pointer really crossed the (now different) rect edge.
            self.pointerMoved(toGlobal: NSEvent.mouseLocation)
        }
    }
}

/// Hosts the island and shows its context menu on a secondary click.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var contextMenu: NSMenu?

    override func rightMouseDown(with event: NSEvent) {
        guard let contextMenu else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    /// Control-click asks for the menu through this hook.
    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu
    }
}
