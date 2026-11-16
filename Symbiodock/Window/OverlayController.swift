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
    private let onCommand: (PlaybackCommand, NowPlayingOrigin) -> Void
    private let onVolume: (VolumeRequest) -> Void
    private let onOpenSession: (AgentSession) -> Void
    private let previews: FilePreviews?
    private let onFile: (FileRequest) -> Void
    private var panel: OverlayPanel?
    private var metrics: ScreenMetrics?
    private var screenObserver: NSObjectProtocol?
    private var tracker: MouseTracker?
    private var pointerInside = false
    /// Whether the pointer is on the bubble beside the island, as of its last move.
    private var pointerOnBubble = false
    private var hoverTask: Task<Void, Never>?
    private var dragMonitor: Any?
    /// Where the button went down on the island (panel-local), until it comes up again.
    private var pressLocation: CGPoint?
    /// False when the press began on a control that is dragged itself (a slider).
    private var pressAllowsDrag = true
    private var settleTask: Task<Void, Never>?
    /// When the current settle is due to end; the pointer poll enforces it if the timer is lost.
    private var settleDeadline: ContinuousClock.Instant?

    /// Files dropped on the island or on a bubble.
    var onDropFiles: ([URL]) -> Void = { _ in }
    /// A tile's file was taken by the app it was dragged to.
    var onFileDraggedOut: (UUID) -> Void = { _ in }
    /// The file a tile holds; nil while it converts or once it is gone: such a tile is not dragged.
    var fileURL: (UUID) -> URL? = { _ in nil }
    /// What the dragged file looks like under the pointer.
    var dragImage: (UUID) -> NSImage? = { _ in nil }
    /// The tile a press went down on, until the press travels or comes up.
    private var pressedFileID: UUID?
    /// The tile whose file is being dragged out, until the drag ends.
    private var outgoingFileID: UUID?
    /// Kept for the session: AppKit does not promise to keep its source alive.
    private var fileDragSource: FileDragSource?

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
        state.setFileDragHovering(false)
        state.setHovering(false)
        pointerInside = false
        pointerOnBubble = false
        tracker?.setSupplementalPolling(false)
    }

    /// The bubble's hover area while there is a bubble.
    private var bubbleHitRect: CGRect? {
        guard let tab = state.bubbleTab else { return nil }
        return IslandLayout.bubbleHitRect(
            notch: geometry.notch, screenSize: geometry.screenSize,
            hasBehind: tab == .media && state.mediaSlots.count > 1)
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
            pressedFileID = nil
        }

        let hitRect = IslandLayout.hitRect(
            anchor: state.anchor, phase: state.phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
        let local = metrics.localPoint(fromGlobal: point)
        // Read again when the hover fires: the pointer may have moved on to the island.
        pointerOnBubble = bubbleHitRect?.contains(local) ?? false
        let inside = pointerOnBubble || hitRect.contains(local)
        let takesDrop = inside || dragIsOverFilesBubble(local)

        // Assign only on change: this runs on every mouse move system-wide.
        setAcceptsMouse(takesDrop)
        endStaleFileDragHover(onTarget: takesDrop)

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
            // Resting on the bubble opens the island on the bubble's tab.
            let tab = inside && self.pointerOnBubble ? self.state.bubbleTab : nil
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
            pressedFileID = pressLocation.flatMap(fileTile(at:))
            // A press on a tile drags its file, never the island.
            if pressedFileID != nil { pressAllowsDrag = false }
        case .leftMouseDragged:
            if state.isDragging {
                continueDrag(to: point)
            } else if pressedFileID != nil {
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
            releaseFilePress(at: point)
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
        pressedFileID = nil
        state.cancelDrag()
    }
}

// MARK: - Dropping files in

extension OverlayController {
    /// The panel takes file drags where the island or a bubble is; anywhere else it lets
    /// events through as usual, so it is never in the way of a drag meant for another app.
    private func acceptFileDrops(on view: IslandHostingView<IslandView>) {
        view.registerForDraggedTypes(FileDropReader.types)
        FileDropReader.log.debug("drop target registered \(view.registeredDraggedTypes.count) types")
        view.fileDragMoved = { [weak self] point, pasteboard, entered in
            self?.fileDragMoved(to: point, pasteboard: pasteboard, entered: entered) ?? []
        }
        view.onFileDragLeft = { [weak self] in self?.fileDragLeft() }
        view.performFileDrop = { [weak self] pasteboard in self?.performFileDrop(pasteboard) ?? false }
    }

    /// The files bubble's hover area while it is shown.
    private var filesBubbleHitRect: CGRect? {
        guard state.filesBubbleShown else { return nil }
        return IslandLayout.filesBubbleHitRect(
            notch: geometry.notch, screenSize: geometry.screenSize, showsWings: state.showsWings,
            behind: max(state.shelf.bubbleKinds.count - 1, 0))
    }

    /// A drag carried onto the files bubble may be dropped there, so the panel must take events
    /// under it while the button is held. It does not open the island: a press that only
    /// happens to be held there (a menu bar icon) must not, and a file drag opens it on entering.
    private func dragIsOverFilesBubble(_ point: CGPoint) -> Bool {
        guard filesBubbleHitRect?.contains(point) == true else { return false }
        return NSEvent.pressedMouseButtons & 1 != 0
    }

    /// AppKit may not say that a drag left when the panel stops taking events under it, nor
    /// when it was cancelled over the island: the drop look must not outlive the drag.
    private func endStaleFileDragHover(onTarget: Bool) {
        guard state.isFileDragHovering, !onTarget || NSEvent.pressedMouseButtons & 1 == 0 else { return }
        FileDropReader.log.debug("file drag hover ended from the pointer poll")
        state.setFileDragHovering(false)
    }

    private func fileDragMoved(to point: CGPoint, pasteboard: NSPasteboard, entered: Bool) -> NSDragOperation {
        let isOwn = outgoingFileID != nil
        let readable = FileDropReader.canRead(pasteboard)
        let onTarget = IslandLayout.hitRect(
            anchor: state.anchor, phase: state.phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings
        ).contains(point)
            || bubbleHitRect?.contains(point) == true
            || filesBubbleHitRect?.contains(point) == true
        if entered {
            FileDropReader.log.notice(
                "file drag entered at \(Int(point.x)),\(Int(point.y)); own: \(isOwn), readable: \(readable), resting: \(self.isIdle), on island: \(onTarget)")
        }
        guard !isOwn, isIdle, readable, onTarget else { return [] }
        if !state.isFileDragHovering {
            // Open on Files at once: no hover delay for a drag on its way in.
            hoverTask?.cancel()
            hoverTask = nil
            pointerInside = true
            state.setFileDragHovering(true)
            FileDropReader.log.notice("file drag accepted; island opens on Files")
        }
        return .copy
    }

    private func fileDragLeft() {
        state.setFileDragHovering(false)
        refreshPointer()
    }

    private func performFileDrop(_ pasteboard: NSPasteboard) -> Bool {
        let taken = FileDropReader.read(pasteboard, storage: .shared) { [weak self] urls in
            self?.onDropFiles(urls)
        }
        FileDropReader.log.notice("file drop performed; taken: \(taken)")
        if taken { Haptics.tick() }
        return taken
    }
}

// MARK: - Dragging files out

extension OverlayController {
    /// The tile under a press on the open Files page, unless it is scrolled out of view.
    private func fileTile(at point: CGPoint) -> UUID? {
        guard state.phase == .expanded, state.selectedTab == .files else { return nil }
        let id = geometry.fileDragViewport.contains(point)
            ? geometry.fileDragRects.first { $0.value.contains(point) }?.key : nil
        FileDragSource.log.debug(
            "press on the Files page; on a tile: \(id != nil), tiles: \(self.geometry.fileDragRects.count), in row: \(self.geometry.fileDragViewport.contains(point))")
        return id
    }

    /// Past the threshold a press on a tile becomes a drag of its file, once. A tile whose file
    /// is converting stays where it is, and the press is no longer a click.
    private func continueFilePress(to point: CGPoint, event: NSEvent) {
        guard let id = pressedFileID, let press = pressLocation,
              hypot(point.x - press.x, point.y - press.y) > Self.dragThreshold else { return }
        pressedFileID = nil
        guard beginFileDrag(id, event: event) else { return }
        // Held, the press would keep the full-screen panel taking events, and it would swallow
        // the drop meant for the app below.
        pressLocation = nil
        refreshPointer()
    }

    private func beginFileDrag(_ id: UUID, event: NSEvent) -> Bool {
        guard let view = panel?.contentView, let url = fileURL(id),
              let tile = geometry.fileDragRects[id] else {
            FileDragSource.log.notice("file drag not started: the tile has no file to give")
            return false
        }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        // The preview sits 6 pt below the tile's top edge (`FileTile`).
        let preview = CGRect(x: tile.midX - 24, y: tile.minY + 6, width: 48, height: 48)
        item.setDraggingFrame(
            preview, contents: dragImage(id) ?? NSWorkspace.shared.icon(forFile: url.path))
        let source = FileDragSource(
            onMoved: { [weak self] in self?.refreshPointer() },
            onEnded: { [weak self] dropped in self?.fileDragEnded(dropped: dropped) })
        let session = view.beginDraggingSession(with: [item], event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
        fileDragSource = source
        outgoingFileID = id
        FileDragSource.log.notice("file drag began")
        return true
    }

    private func fileDragEnded(dropped: Bool) {
        let id = outgoingFileID
        outgoingFileID = nil
        fileDragSource = nil
        FileDragSource.log.notice("file drag ended; dropped: \(dropped)")
        if dropped, let id { onFileDraggedOut(id) }
        refreshPointer()
    }

    /// A press on a tile that never travelled is a click: it selects the tile.
    private func releaseFilePress(at point: CGPoint) {
        guard let id = pressedFileID else { return }
        pressedFileID = nil
        guard geometry.fileDragRects[id]?.contains(point) == true else { return }
        state.selectShelfItem(id)
    }
}

/// Hosts the island, shows its context menu on a secondary click and takes file drops.
private final class IslandHostingView<Content: View>: NSHostingView<Content> {
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
