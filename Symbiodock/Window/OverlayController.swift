import AppKit
import SwiftUI
import SymbiodockCore

/// Owns the overlay panel, keeps it matched to the island's display, and turns the
/// pointer into hover state, click-through and drags.
@MainActor
final class OverlayController {
    /// Switch to `.polling` if event monitors do not deliver pointer movement.
    private static let trackerMode: MouseTracker.Mode = .eventMonitors
    /// How far the pointer must travel with the button down before a click becomes a drag.
    private static let dragThreshold: CGFloat = 6
    /// Long enough for the released island to glide into place (see `DragSession.spring`).
    private static let settleDuration: Duration = .milliseconds(550)

    private let state: IslandState
    private let geometry = IslandGeometry()
    private let session = DragSession()
    private let contextMenu: NSMenu
    private let onCommand: (PlaybackCommand) -> Void
    private var panel: OverlayPanel?
    private var metrics: ScreenMetrics?
    private var screenObserver: NSObjectProtocol?
    private var tracker: MouseTracker?
    private var pointerInside = false
    private var hoverTask: Task<Void, Never>?
    private var dragMonitor: Any?
    /// Where the button went down on the island (panel-local), until it comes up again.
    private var pressLocation: CGPoint?
    private var settleTask: Task<Void, Never>?

    init(
        state: IslandState, contextMenu: NSMenu,
        onCommand: @escaping (PlaybackCommand) -> Void
    ) {
        self.state = state
        self.contextMenu = contextMenu
        self.onCommand = onCommand
    }

    func start() {
        state.restoreAnchor(AnchorStore.load())

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
        installDragMonitor()
    }

    /// Puts the island back on the notch. Ignored while it is being dragged or settling.
    func returnToNotch() {
        guard state.phase == .collapsed || state.phase == .expanded else { return }
        state.restoreAnchor(.notch)
        AnchorStore.save(.notch)
        refreshPointer()
    }

    // MARK: Panel

    /// Recreates the panel for the current display configuration.
    private func rebuildPanel() {
        guard let screen = NSScreen.islandScreen else {
            abortDrag()
            resetHoverState()
            panel?.close()
            panel = nil
            metrics = nil
            return
        }
        let metrics = ScreenMetrics(screen: screen)
        // Nothing changed (e.g. unrelated screen-parameter notification): keep the panel.
        if panel != nil, metrics == self.metrics { return }
        // Only the visible frame moved (Dock or menu bar auto-hide): rebuilding would collapse
        // the island. A floating island follows through the observable geometry instead.
        if panel != nil, var stored = self.metrics {
            stored.visibleFrame = metrics.visibleFrame
            if stored == metrics {
                self.metrics = metrics
                geometry.visibleFrame = metrics.localVisibleFrame
                refreshPointer()
                return
            }
        }

        abortDrag()
        resetHoverState()
        panel?.close()
        panel = nil

        self.metrics = metrics
        geometry.notch = NotchGeometry.notchRect(for: metrics)
        geometry.visibleFrame = metrics.localVisibleFrame
        geometry.screenSize = metrics.frame.size
        geometry.hasPhysicalNotch = metrics.hasNotch

        let panel = OverlayPanel(screenFrame: metrics.frame)
        let hostingView = IslandHostingView(rootView: IslandView(
            state: state, geometry: geometry, session: session, onCommand: onCommand))
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

    /// The island's frame at its anchor, in panel-local coordinates.
    private func islandFrame(phase: IslandPhase) -> CGRect {
        IslandLayout.frame(
            anchor: state.anchor, phase: phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            hasTrack: state.showsWings)
    }

    /// Clicks reach the panel only while this is on. While the panel accepts events the
    /// global monitor is blind, so poll as a safety net against a lost exit or mouse-up.
    private func setAcceptsMouse(_ accepts: Bool) {
        guard let panel, panel.ignoresMouseEvents == accepts else { return }
        panel.ignoresMouseEvents = !accepts
        tracker?.setSupplementalPolling(accepts)
    }

    // MARK: Hover

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
        guard let metrics, panel != nil else { return }

        if state.isDragging || state.phase == .settling {
            // The island is wherever the pointer takes it; keep receiving its events.
            setAcceptsMouse(true)
            // A mouse-up can get lost (released over a system dialog, during a Space switch).
            if state.isDragging, NSEvent.pressedMouseButtons & 1 == 0 {
                endDrag()
            }
            return
        }

        let hitRect = IslandLayout.hitRect(
            anchor: state.anchor, phase: state.phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            hasTrack: state.showsWings)
        let inside = hitRect.contains(metrics.localPoint(fromGlobal: point))

        // Assign only on change: this runs on every mouse move system-wide.
        setAcceptsMouse(inside)

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

    // MARK: Dragging

    /// Drags are recognised from raw mouse events, not a SwiftUI gesture: the view under the
    /// pointer is replaced when the drag starts, which would cancel a gesture attached to it.
    private func installDragMonitor() {
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            let type = event.type
            let windowNumber = event.windowNumber
            // Control-click opens the menu; it must never start a drag.
            let isControlClick = event.modifierFlags.contains(.control)
            MainActor.assumeIsolated {
                self?.handleMouse(type, windowNumber: windowNumber, isControlClick: isControlClick)
            }
            return event
        }
    }

    private func handleMouse(_ type: NSEvent.EventType, windowNumber: Int, isControlClick: Bool) {
        guard let metrics, let panel else { return }
        let point = metrics.localPoint(fromGlobal: NSEvent.mouseLocation)

        switch type {
        case .leftMouseDown:
            let idle = state.phase == .collapsed || state.phase == .expanded
            let onIsland = islandFrame(phase: state.phase)
                .insetBy(dx: -IslandLayout.hitPadding, dy: -IslandLayout.hitPadding)
                .contains(point)
            pressLocation =
                windowNumber == panel.windowNumber && !isControlClick && idle && onIsland ? point : nil
        case .leftMouseDragged:
            if state.isDragging {
                continueDrag(to: point)
            } else if let press = pressLocation,
                      hypot(point.x - press.x, point.y - press.y) > Self.dragThreshold {
                beginDrag(from: press)
                continueDrag(to: point)
            }
        case .leftMouseUp:
            pressLocation = nil
            if state.isDragging { endDrag() }
        default:
            break
        }
    }

    private func beginDrag(from press: CGPoint) {
        hoverTask?.cancel()
        hoverTask = nil
        pointerInside = false
        settleTask?.cancel()

        // The island is always collapsed while it is dragged.
        let resting = islandFrame(phase: .collapsed)
        let atNotch = state.anchor == .notch
        state.beginDrag(at: press, from: CGPoint(x: resting.midX, y: resting.midY))
        guard state.isDragging else { return }
        session.begin(
            restingFrame: resting,
            // Pulled off the notch, the goo hangs from the notch itself, not from the wings.
            rootRect: atNotch ? geometry.notch : resting,
            rootAtNotch: atNotch,
            rootIsPhysicalNotch: atNotch && geometry.hasPhysicalNotch)
        setAcceptsMouse(true)
    }

    private func continueDrag(to point: CGPoint) {
        let tore = state.drag(to: point)
        if let offset = state.dragOffset {
            session.move(by: offset)
        }
        if tore {
            // State and effect tear on the same event, so they cannot disagree.
            session.tear()
            Self.haptic(.levelChange)
        }
    }

    private func endDrag() {
        guard state.isDragging else { return }
        let wasDetached = state.phase == .detached
        let resolved = SnapResolver.anchor(
            forRelease: session.bodyCenter, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame)
        state.endDrag(resolvedAnchor: resolved)
        session.settle(into: islandFrame(phase: .collapsed))
        if wasDetached {
            AnchorStore.save(state.anchor)
            Self.haptic(.alignment)
        }

        // Not tied to the animation finishing: a timer cannot get lost.
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDuration)
            guard !Task.isCancelled, let self else { return }
            self.state.finishSettling()
            self.refreshPointer()
        }
    }

    /// Leaves any drag at once, for when the panel goes away under it.
    private func abortDrag() {
        settleTask?.cancel()
        settleTask = nil
        pressLocation = nil
        state.cancelDrag()
    }

    /// Felt on the trackpad only; a mouse has nothing to move.
    private static func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// Hosts the island and shows its context menu on a secondary click.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var contextMenu: NSMenu?

    /// A click on a panel that never becomes key would otherwise only "activate" it;
    /// the island's buttons must react to the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
