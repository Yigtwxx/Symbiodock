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
    static let dragThreshold: CGFloat = 6
    /// Long enough for the released island to glide into place (see `DragSession.spring`).
    private static let settleDuration: Duration = .milliseconds(550)

    // Not private where the Files code (`OverlayController+Files.swift`) needs them too.
    let state: IslandState
    let geometry = IslandGeometry()
    private let session = DragSession()
    private let contextMenu: NSMenu
    private let onCommand: (PlaybackCommand, NowPlayingOrigin) -> Void
    private let onVolume: (VolumeRequest) -> Void
    private let onOpenSession: (AgentSession) -> Void
    private let previews: FilePreviews?
    private let onFile: (FileRequest) -> Void
    private(set) var panel: OverlayPanel?
    private var metrics: ScreenMetrics?
    private var screenObserver: NSObjectProtocol?
    private var tracker: MouseTracker?
    var pointerInside = false
    var hoverTask: Task<Void, Never>?
    private var dragMonitor: Any?
    /// Where the button went down on the island (panel-local), until it comes up again.
    var pressLocation: CGPoint?
    /// False when the press began on a control that is dragged itself (a slider).
    private var pressAllowsDrag = true
    private var settleTask: Task<Void, Never>?
    /// When the current settle is due to end; the pointer poll enforces it if the timer is lost.
    private var settleDeadline: ContinuousClock.Instant?

    /// Files dropped on the island or on a bubble, and where that drop puts them. A drop's
    /// files can arrive in several calls; each names the same place.
    var onDropFiles: (_ urls: [URL], _ onto: ShelfDropPlace) -> Void = { _, _ in }
    /// Files dragged within the island: with a stack they join it in front; without, each
    /// becomes a tile of its own.
    var onMoveFiles: (_ ids: [UUID], _ onto: UUID?) -> Void = { _, _ in }
    /// Files taken by the app they were dragged to.
    var onFilesDraggedOut: ([UUID]) -> Void = { _ in }
    /// The file a tile holds; nil while it converts or once it is gone: such a tile is not dragged.
    var fileURL: (UUID) -> URL? = { _ in nil }
    /// What the dragged file looks like under the pointer.
    var dragImage: (UUID) -> NSImage? = { _ in nil }
    /// A click without travel on a stack: which stack, where on it, and whether ⌘ was held.
    var onPickFile: (_ stack: UUID, StackLayout.Hit, _ command: Bool) -> Void = { _, _, _ in }
    /// Where on a stack a press went down, until the press travels or comes up.
    var pressedFile: ShelfHover?
    /// Files being dragged out of the shelf, until the drag ends.
    var outgoing: OutgoingFileDrag?
    /// After a click reordered a drawer, the pointer still rests where it was; until it moves
    /// off this point, no card rises under it.
    var hoverHeldAt: CGPoint?

    /// Drag milestones only (phase names and booleans, never content). Watch with:
    /// `log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "drag"'`
    private static let dragLog = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "drag")

    init(
        state: IslandState, contextMenu: NSMenu,
        onCommand: @escaping (PlaybackCommand, NowPlayingOrigin) -> Void,
        onVolume: @escaping (VolumeRequest) -> Void,
        onOpenSession: @escaping (AgentSession) -> Void,
        previews: FilePreviews?,
        onFile: @escaping (FileRequest) -> Void
    ) {
        self.state = state
        self.contextMenu = contextMenu
        self.onCommand = onCommand
        self.onVolume = onVolume
        self.onOpenSession = onOpenSession
        self.previews = previews
        self.onFile = onFile
        session.onCatch = {
            Self.dragLog.notice("strands caught a surface")
            Haptics.tick()
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
            state: state, geometry: geometry, session: session, onCommand: onCommand,
            onVolume: onVolume, onOpenSession: onOpenSession, previews: previews, onFile: onFile))
        hostingView.contextMenu = contextMenu
        // A menu opened mid-drag would freeze the island where it is.
        hostingView.allowsContextMenu = { [weak self] in self?.isIdle ?? false }
        // Keep SwiftUI from resizing the panel to the content's ideal size.
        hostingView.sizingOptions = []
        acceptFileDrops(on: hostingView)
        panel.contentView = hostingView
        panel.setFrame(metrics.frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        // The new panel ignores mouse events; re-check in case the pointer is already on the island.
        pointerMoved(toGlobal: NSEvent.mouseLocation)
    }

    /// Neither dragged nor settling.
    var isIdle: Bool {
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
        state.setFileDragHovering(false)
        state.setHovering(false)
        pointerInside = false
        tracker?.setSupplementalPolling(false)
    }

    /// The area in which the pointer counts as on the island, in panel-local coordinates.
    var islandHitRect: CGRect {
        IslandLayout.hitRect(
            anchor: state.anchor, phase: state.phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
    }

    /// While another app drags files with the island at the notch, the whole area the open
    /// island will cover takes the drag. Waiting at the screen's top edge opens Mission
    /// Control, so the person must be able to drop below the notch instead.
    var fileApproachRect: CGRect? {
        guard state.anchor == .notch, outgoing == nil, pressLocation == nil,
              NSEvent.pressedMouseButtons & 1 != 0,
              FileDropReader.canRead(NSPasteboard(name: .drag))
        else { return nil }
        // A band just around the closed island, not the open island's whole area: windows
        // below it must still take files dropped on them (owner: "biraz daha yaklaşmam gereksin").
        var band = IslandLayout.hitRect(
            anchor: state.anchor, phase: .collapsed, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
        band = band.insetBy(dx: -Self.fileApproachMargin, dy: 0)
        band.size.height += Self.fileApproachMargin
        return band
    }

    /// How far around the closed island a file drag opens it.
    static let fileApproachMargin: CGFloat = 36

    /// The bubble's hover area while there is a bubble.
    var bubbleHitRect: CGRect? {
        guard let tab = state.bubbleTab else { return nil }
        return IslandLayout.bubbleHitRect(
            notch: geometry.notch, screenSize: geometry.screenSize,
            hasBehind: tab == .media && state.mediaSlots.count > 1)
    }

    /// The files bubble's hover area while it is shown, with the discs behind it.
    var filesBubbleHitRect: CGRect? {
        guard state.filesBubbleShown else { return nil }
        return IslandLayout.filesBubbleHitRect(
            notch: geometry.notch, screenSize: geometry.screenSize, showsWings: state.showsWings,
            behind: max(state.shelf.bubbleKinds.count - 1, 0))
    }

    /// The tab of the bubble under a panel-local point.
    private func bubbleTab(at point: CGPoint) -> IslandTab? {
        if bubbleHitRect?.contains(point) == true { return state.bubbleTab }
        if filesBubbleHitRect?.contains(point) == true { return .files }
        return nil
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
            pressedFile = nil
        }

        let hitRect = islandHitRect
        let local = metrics.localPoint(fromGlobal: point)
        // A bubble takes clicks, hovers and file drops just as the island does.
        let inside = bubbleTab(at: local) != nil || hitRect.contains(local)
            || fileApproachRect?.contains(local) == true

        // Assign only on change: this runs on every mouse move system-wide.
        setAcceptsMouse(inside)
        endStaleFileDragHover(onTarget: inside)
        updateFileHover(at: local, onIsland: hitRect.contains(local))

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
            var tab: IslandTab?
            if inside {
                // Read now, not at the last move: the left bubble may have changed its tab
                // during the delay, or the files bubble gone with the shelf's last file.
                let local = metrics.localPoint(fromGlobal: NSEvent.mouseLocation)
                tab = self.bubbleTab(at: local)
                // A bubble that went away opens nothing; the re-check below lets go.
                guard tab != nil || self.islandHitRect.contains(local) else {
                    self.pointerMoved(toGlobal: NSEvent.mouseLocation)
                    return
                }
            }
            // Resting on a bubble opens the island on the bubble's tab.
            self.state.setHovering(inside, opening: tab)
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
            // Local monitors run on the main thread; the event goes on to the panel unchanged.
            MainActor.assumeIsolated { self?.handleMouse(event) }
            return event
        }
    }

    private func handleMouse(_ event: NSEvent) {
        guard let metrics, let panel else { return }
        var point = metrics.localPoint(fromGlobal: NSEvent.mouseLocation)
        // Dragging between displays is not supported: the island stays on its own.
        point.x = min(max(point.x, 0), geometry.screenSize.width)
        point.y = min(max(point.y, 0), geometry.screenSize.height)

        switch event.type {
        case .leftMouseDown:
            let onIsland = islandFrame(phase: state.phase)
                .insetBy(dx: -IslandLayout.hitPadding, dy: -IslandLayout.hitPadding)
                .contains(point)
            // Control-click opens the menu; it must never start a drag.
            let isControlClick = event.modifierFlags.contains(.control)
            pressLocation =
                event.windowNumber == panel.windowNumber && !isControlClick && isIdle && onIsland
                ? point : nil
            // The press is still tracked, so the island stays open while a slider is dragged
            // past its edge; it only never becomes a drag of the island.
            pressAllowsDrag = !(state.phase == .expanded
                && geometry.noDragRects.values.contains { $0.contains(point) })
            pressedFile = pressLocation.flatMap(filePress(at:))
            // A press on a stack drags its files, never the island.
            if pressedFile != nil { pressAllowsDrag = false }
        case .leftMouseDragged:
            if state.isDragging {
                continueDrag(to: point)
            } else if pressedFile != nil {
                continueFilePress(to: point, event: event)
            } else if let press = pressLocation, pressAllowsDrag, isIdle,
                      hypot(point.x - press.x, point.y - press.y) > Self.dragThreshold {
                // One press starts at most one drag: a drag event still queued after the
                // release must not start a second one.
                pressLocation = nil
                beginDrag(from: press)
                continueDrag(to: point)
            }
        case .leftMouseUp:
            releaseFilePress(at: point, command: event.modifierFlags.contains(.command))
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
            Haptics.tick()
        }
    }

    private func endDrag() {
        guard state.isDragging else { return }
        pressLocation = nil
        let wasDetached = state.phase == .detached
        // Strands holding a surface decide where the island goes; otherwise the nearest place.
        let held = session.heldSurface
        let resolved = SnapResolver.anchor(
            forRelease: session.bodyCenter, attachedTo: held, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame)
        state.endDrag(resolvedAnchor: resolved)
        session.settle(into: islandFrame(phase: .collapsed), anchor: state.anchor)
        Self.dragLog.notice("drag ended; detached: \(wasDetached), held: \(held != nil)")
        if wasDetached {
            AnchorStore.save(state.anchor)
            // The island sticks now, caught or not: a firm tick while the finger is still on
            // the trackpad. A caught island also ticked when its strands took hold.
            Haptics.tick()
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
        pressedFile = nil
        state.cancelDrag()
    }
}

/// Hosts the island, shows its context menu on a secondary click and takes file drops.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var contextMenu: NSMenu?
    /// Asked before the menu opens.
    var allowsContextMenu: () -> Bool = { true }
    /// A file drag entered (`entered`) or moved, at a panel-local point: what it may do here.
    var fileDragMoved: (_ point: CGPoint, _ pasteboard: NSPasteboard, _ entered: Bool) -> NSDragOperation =
        { _, _, _ in [] }
    /// The drag left the panel or ended, dropped or not.
    var onFileDragLeft: () -> Void = {}
    /// The drag was let go over a place `fileDragMoved` accepted.
    var performFileDrop: (_ pasteboard: NSPasteboard) -> Bool = { _ in false }

    // NSHostingView answers every destination call for SwiftUI's own drop modifiers. The island
    // has none, so each call is taken here and none reaches it. The view is flipped, so a point
    // converted from the window is panel-local.

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileDragMoved(convert(sender.draggingLocation, from: nil), sender.draggingPasteboard, true)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileDragMoved(convert(sender.draggingLocation, from: nil), sender.draggingPasteboard, false)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDragLeft()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onFileDragLeft()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        performFileDrop(sender.draggingPasteboard)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {}

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
