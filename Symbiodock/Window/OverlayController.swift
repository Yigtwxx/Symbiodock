import AppKit
import SwiftUI
import SymbiodockCore
import os

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
    /// When the current settle is due to end; the pointer poll enforces it if the timer is lost.
    private var settleDeadline: ContinuousClock.Instant?

    /// Drag milestones only (phase names and booleans, never content). Watch with:
    /// `log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "drag"'`
    private static let dragLog = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "drag")

    init(
        state: IslandState, contextMenu: NSMenu,
        onCommand: @escaping (PlaybackCommand) -> Void
    ) {
        self.state = state
        self.contextMenu = contextMenu
        self.onCommand = onCommand
        session.onCatch = {
            Self.dragLog.notice("strands caught a surface")
            Self.haptic(.alignment)
        }
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
        guard isIdle else { return }
        // Fly there collapsed; the pointer is on the menu, not on the island.
        hoverTask?.cancel()
        hoverTask = nil
        pointerInside = false
        state.setHovering(false)
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
        // A menu opened mid-drag would freeze the island where it is.
        hostingView.allowsContextMenu = { [weak self] in self?.isIdle ?? false }
        // Keep SwiftUI from resizing the panel to the content's ideal size.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(metrics.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // The new panel ignores mouse events; re-check in case the pointer is already on the island.
        pointerMoved(toGlobal: NSEvent.mouseLocation)
    }

    /// Neither dragged nor settling.
    private var isIdle: Bool {
        state.phase == .collapsed || state.phase == .expanded
    }

    /// The island's frame at its anchor, in panel-local coordinates.
    private func islandFrame(phase: IslandPhase) -> CGRect {
        IslandLayout.frame(
            anchor: state.anchor, phase: phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
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

        if state.isDragging {
            // The island is wherever the pointer takes it; keep receiving its events.
            setAcceptsMouse(true)
            // A mouse-up can get lost (released over a system dialog, during a Space switch).
            if NSEvent.pressedMouseButtons & 1 == 0 {
                Self.dragLog.notice("mouse-up was lost; ending the drag from the pointer poll")
                endDrag()
            }
            return
        }
        if state.phase == .settling {
            // Nothing takes clicks while the island glides: the panel covers the whole display,
            // so holding it here would swallow every click on it.
            setAcceptsMouse(false)
            if let settleDeadline, ContinuousClock.now > settleDeadline + .milliseconds(250) {
                Self.dragLog.notice("settle timer was lost; finishing from the pointer poll")
                finishSettling()
            }
            return
        }
        if pressLocation != nil {
            // The button is down on the island but the drag has not started: keep the events
            // coming even if the pointer slips off the island within the drag threshold.
            if NSEvent.pressedMouseButtons & 1 != 0 {
                setAcceptsMouse(true)
                return
            }
            pressLocation = nil
        }

        let hitRect = IslandLayout.hitRect(
            anchor: state.anchor, phase: state.phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
        let inside = hitRect.contains(metrics.localPoint(fromGlobal: point))

        // Assign only on change: this runs on every mouse move system-wide.
        setAcceptsMouse(inside)

        guard inside != pointerInside else { return }
        pointerInside = inside

        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: inside ? HoverTiming.enterDelay : HoverTiming.exitDelay)
            guard !Task.isCancelled, let self else { return }
            // A press that may become a drag must not have the island open under it;
            // the pointer is re-checked when the button comes up.
            if inside, self.pressLocation != nil {
                self.pointerInside = false
                return
            }
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
        var point = metrics.localPoint(fromGlobal: NSEvent.mouseLocation)
        // Dragging between displays is not supported: the island stays on its own.
        point.x = min(max(point.x, 0), geometry.screenSize.width)
        point.y = min(max(point.y, 0), geometry.screenSize.height)

        switch type {
        case .leftMouseDown:
            let onIsland = islandFrame(phase: state.phase)
                .insetBy(dx: -IslandLayout.hitPadding, dy: -IslandLayout.hitPadding)
                .contains(point)
            pressLocation =
                windowNumber == panel.windowNumber && !isControlClick && isIdle && onIsland ? point : nil
        case .leftMouseDragged:
            if state.isDragging {
                continueDrag(to: point)
            } else if let press = pressLocation, isIdle,
                      hypot(point.x - press.x, point.y - press.y) > Self.dragThreshold {
                // One press starts at most one drag: a drag event still queued after the
                // release must not start a second one.
                pressLocation = nil
                beginDrag(from: press)
                continueDrag(to: point)
            }
        case .leftMouseUp:
            let wasPressed = pressLocation != nil
            pressLocation = nil
            if state.isDragging {
                endDrag()
            } else if wasPressed {
                // Hover was held back during the press; pick it up again.
                refreshPointer()
            }
        default:
            break
        }
    }

    private func beginDrag(from press: CGPoint) {
        // The island is always collapsed while it is dragged; it shrinks from what it is now.
        let current = islandFrame(phase: state.phase)
        let resting = islandFrame(phase: .collapsed)
        let atNotch = state.anchor == .notch
        state.beginDrag(at: press, from: CGPoint(x: resting.midX, y: resting.midY))
        // Tear nothing down unless the drag really began.
        guard state.isDragging else { return }
        hoverTask?.cancel()
        hoverTask = nil
        pointerInside = false
        Self.dragLog.notice("drag began; at notch: \(atNotch)")
        session.begin(
            currentFrame: current, restingFrame: resting, press: press,
            // Pulled off the notch, the goo hangs from the notch itself, not from the wings.
            rootRect: atNotch ? geometry.notch : resting,
            rootAnchor: state.anchor,
            rootIsPhysicalNotch: atNotch && geometry.hasPhysicalNotch,
            notch: geometry.notch, visibleFrame: geometry.visibleFrame,
            hasPhysicalNotch: geometry.hasPhysicalNotch)
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
            Self.dragLog.notice("island tore off")
            Self.haptic(.levelChange)
        }
    }

    private func endDrag() {
        guard state.isDragging else { return }
        pressLocation = nil
        let wasDetached = state.phase == .detached
        // Strands holding a surface decide where the island goes; otherwise the nearest place.
        let held = session.heldSurface
        let wasCaught = session.hasCaughtSurface
        let resolved = SnapResolver.anchor(
            forRelease: session.bodyCenter, attachedTo: held, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame)
        state.endDrag(resolvedAnchor: resolved)
        session.settle(into: islandFrame(phase: .collapsed), anchor: state.anchor)
        Self.dragLog.notice("drag ended; detached: \(wasDetached), held: \(held != nil)")
        if wasDetached {
            AnchorStore.save(state.anchor)
            // An island already caught by its strands gave its tick when they took hold.
            if !wasCaught { Self.haptic(.alignment) }
        }
        // The glide needs no clicks; give the display back at once.
        setAcceptsMouse(false)

        // Not tied to the animation finishing; and if this timer is ever lost, the pointer
        // poll finishes the settle from `settleDeadline`.
        settleDeadline = .now + Self.settleDuration
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDuration)
            guard !Task.isCancelled else { return }
            self?.finishSettling()
        }
    }

    private func finishSettling() {
        settleTask?.cancel()
        settleTask = nil
        settleDeadline = nil
        guard state.phase == .settling else { return }
        state.finishSettling()
        Self.dragLog.notice("settled")
        refreshPointer()
    }

    /// Leaves any drag at once, for when the panel goes away under it.
    private func abortDrag() {
        settleTask?.cancel()
        settleTask = nil
        settleDeadline = nil
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
    /// Asked before the menu opens.
    var allowsContextMenu: () -> Bool = { true }

    /// A click on a panel that never becomes key would otherwise only "activate" it;
    /// the island's buttons must react to the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        guard allowsContextMenu() else { return }
        guard let contextMenu else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    /// Control-click asks for the menu through this hook.
    override func menu(for event: NSEvent) -> NSMenu? {
        allowsContextMenu() ? contextMenu : nil
    }
}
