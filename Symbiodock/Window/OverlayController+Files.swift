import AppKit
import SymbiodockCore

// The Files page's part of the overlay: files dropped in, the pointer over the stacks, a press
// on a stack, files dragged out and the drops the island takes back itself. Called from the
// controller's pointer and mouse handling; nothing here runs at rest.

// MARK: - Dropping files in

extension OverlayController {
    /// The panel takes file drags where the island or a bubble is; anywhere else it lets
    /// events through as usual, so it is never in the way of a drag meant for another app.
    func acceptFileDrops(on view: IslandHostingView<IslandView>) {
        view.registerForDraggedTypes(FileDropReader.types)
        FileDropReader.log.debug("drop target registered \(view.registeredDraggedTypes.count) types")
        view.fileDragMoved = { [weak self] point, pasteboard, entered in
            self?.fileDragMoved(to: point, pasteboard: pasteboard, entered: entered) ?? []
        }
        view.onFileDragLeft = { [weak self] in self?.fileDragLeft() }
        view.performFileDrop = { [weak self] pasteboard in self?.performFileDrop(pasteboard) ?? false }
    }

    /// AppKit may not say that a drag left when the panel stops taking events under it, nor
    /// when it was cancelled over the island: the drop look must not outlive the drag.
    func endStaleFileDragHover(onTarget: Bool) {
        guard state.isFileDragHovering || state.fileDropTarget != nil || state.fileDragSetsApart,
              !onTarget || NSEvent.pressedMouseButtons & 1 == 0 else { return }
        FileDropReader.log.debug("file drag hover ended from the pointer poll")
        state.setFileDragHovering(false)
    }

    /// The stack a drop would join, logged when it changes.
    private func setDropTarget(_ stack: UUID?) {
        guard stack != state.fileDropTarget else { return }
        FileDropReader.log.debug(
            "drop target: \(stack.map(Self.shortID) ?? "none", privacy: .public), files in it: \(stack.flatMap { self.state.shelf.stack($0) }?.items.count ?? 0)")
        state.setFileDropTarget(stack)
    }

    /// Enough of an id to follow one stack through the log.
    nonisolated fileprivate static func shortID(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }

    private func fileDragMoved(to point: CGPoint, pasteboard: NSPasteboard, entered: Bool) -> NSDragOperation {
        let isOwn = outgoing != nil
        let readable = FileDropReader.canRead(pasteboard)
        let onTarget = islandHitRect.contains(point)
            || bubbleHitRect?.contains(point) == true
            || filesBubbleHitRect?.contains(point) == true
            || fileApproachRect?.contains(point) == true
        if entered {
            FileDropReader.log.notice(
                "file drag entered at \(Int(point.x)),\(Int(point.y)); own: \(isOwn), readable: \(readable), resting: \(self.isIdle), on island: \(onTarget)")
        }
        if isOwn { return ownFilesMoved(to: point, onTarget: onTarget) }
        guard isIdle, readable, onTarget else { return [] }
        if !state.isFileDragHovering {
            takeHoverForFileDrag()
            state.setFileDragHovering(true)
            FileDropReader.log.notice("file drag accepted; island opens on Files")
        }
        let stack = stackBox(at: point)?.id
        // A drawer in its cocoon takes nothing, like the header: no target, no outline.
        if let stack, isConverting(stack) {
            setDropTarget(nil)
            return []
        }
        setDropTarget(stack)
        return .copy
    }

    /// A file drag on its way in opens the island without the hover delay; the pointer counts
    /// as inside, so the hover rule does not open it again on another tab.
    private func takeHoverForFileDrag() {
        hoverTask?.cancel()
        hoverTask = nil
        pointerInside = true
    }

    /// A file of the stack is in its cocoon: the drawer is sealed, nothing goes in or out.
    private func isConverting(_ stack: UUID) -> Bool {
        state.shelf.stack(stack)?.items.contains { state.conversions[$0.id] != nil } ?? false
    }

    /// The shelf's own files over the island: another stack takes them, and so does the
    /// row's empty part when they would come apart from their stack; anywhere else the drop
    /// is refused and they go back where they were. Coming back after the island closed, they
    /// open it on Files, as files from another app do.
    private func ownFilesMoved(to point: CGPoint, onTarget: Bool) -> NSDragOperation {
        guard var drag = outgoing else { return [] }
        if isIdle, onTarget, !filesPageShown {
            takeHoverForFileDrag()
            state.openOnFiles()
            FileDropReader.log.notice("own files came back; island opens on Files")
        }
        let place = isIdle ? ownDropPlace(at: point, for: drag) : nil
        if place != drag.place {
            FileDropReader.log.debug(
                "own files over the island; a drop would \(place?.logName ?? "change nothing", privacy: .public)")
            drag.place = place
            outgoing = drag
        }
        if case .stack(let id) = place { setDropTarget(id) } else { setDropTarget(nil) }
        // Only an indicator that a drop here sets them apart (each lands right after the
        // drawer it left); drawn over the row, it makes no room, so no stack moves under the
        // pointer, and it goes wherever the drop would be refused.
        state.setFileDragSetsApart(place == .apart)
        return place == nil ? [] : .move
    }

    /// Where the island would take its own dragged files at a panel-local point.
    private func ownDropPlace(at point: CGPoint, for drag: OutgoingFileDrag) -> OwnDropPlace? {
        if let (id, _) = stackBox(at: point) {
            // Back on the stack they came from they would change nothing; a drawer in its
            // cocoon takes nothing.
            return id == drag.stack || isConverting(id) ? nil : .stack(id)
        }
        guard filesPageShown, geometry.fileDragViewport.contains(point), !drag.isWholeStack else {
            return nil
        }
        return .apart
    }

    private func fileDragLeft() {
        state.setFileDragHovering(false)
        refreshPointer()
    }

    private func performFileDrop(_ pasteboard: NSPasteboard) -> Bool {
        if outgoing != nil { return takeBackOwnFiles() }
        // One drop, one place, decided now: promised files and images arrive one by one,
        // later, and each joins the stack shown as the target when the drag was let go, or
        // else the one new stack made for this drop.
        let place: ShelfDropPlace = state.fileDropTarget.map { .onto($0) } ?? .newStack(UUID())
        let taken = FileDropReader.read(pasteboard, storage: .shared) { [weak self] urls in
            self?.onDropFiles(urls, place)
        }
        FileDropReader.log.notice(
            "file drop performed; taken: \(taken), \(place.logName, privacy: .public)")
        if taken { Haptics.tick() }
        return taken
    }

    /// The shelf's own files let go over a place that takes them: they change stacks and
    /// stay on the shelf when the drag ends.
    private func takeBackOwnFiles() -> Bool {
        guard var drag = outgoing, let place = drag.place else { return false }
        switch place {
        case .stack(let id):
            FileDropReader.log.notice(
                "own files moved onto stack \(Self.shortID(id), privacy: .public); files: \(drag.ids.count)")
            onMoveFiles(drag.ids, id)
        case .apart:
            FileDropReader.log.notice("own files set apart as tiles of their own; files: \(drag.ids.count)")
            onMoveFiles(drag.ids, nil)
        }
        drag.kept = true
        outgoing = drag
        Haptics.tick()
        return true
    }
}

// MARK: - The pointer and a press on the stacks

extension OverlayController {
    /// The open island shows the Files page.
    private var filesPageShown: Bool {
        state.phase == .expanded && state.selectedTab == .files
    }

    /// The stack whose box holds a panel-local point on the open Files page, unless it is
    /// scrolled out of view.
    private func stackBox(at point: CGPoint) -> (id: UUID, box: CGRect)? {
        guard filesPageShown, geometry.fileDragViewport.contains(point),
              let (id, box) = geometry.fileDragRects.first(where: { $0.value.contains(point) })
        else { return nil }
        return (id, box)
    }

    /// Where on its stack a panel-local point lands; nil off every card.
    private func shelfHit(at point: CGPoint) -> ShelfHover? {
        guard let (id, box) = stackBox(at: point), let stack = state.shelf.stack(id),
              let hit = StackLayout.hit(
                  CGPoint(x: point.x - box.minX, y: point.y - box.minY), count: stack.items.count)
        else { return nil }
        return ShelfHover(stack: id, hit: hit)
    }

    /// While the open island shows Files and no button is down, the card under the pointer
    /// rises; anywhere else nothing does. The state assigns only on change, and this runs on
    /// every pointer move and poll.
    func updateFileHover(at point: CGPoint, onIsland: Bool) {
        if let held = hoverHeldAt {
            guard hypot(point.x - held.x, point.y - held.y) >= 0.5 else {
                state.setHoveredFile(nil)
                return
            }
            hoverHeldAt = nil
        }
        let resting = onIsland && NSEvent.pressedMouseButtons & 1 == 0
        state.setHoveredFile(resting ? shelfHit(at: point) : nil)
    }

    /// What a press takes hold of, decided once where the button goes down; the selection
    /// plays no part. The same answer picks on a click and says what a drag carries (see
    /// `draggedFiles`). Off every card the press is the island's, as on any empty part of
    /// the page, so it can tear the island off.
    func filePress(at point: CGPoint) -> ShelfHover? {
        let press = shelfHit(at: point)
        if let press, let stack = state.shelf.stack(press.stack) {
            FileDragSource.log.debug(
                "press on stack \(Self.shortID(press.stack), privacy: .public) at \(press.hit.logName, privacy: .public); a drag takes \(self.draggedFiles(press, in: stack).count) of its \(stack.items.count) files")
        } else if filesPageShown {
            FileDragSource.log.debug(
                "press on the Files page off every card; stacks: \(self.geometry.fileDragRects.count), in row: \(self.geometry.fileDragViewport.contains(point))")
        }
        return press
    }

    /// A press on a stack that never travelled is a click: it picks what the press went down
    /// on. If that reordered the drawer, the card now under the pointer is another file; it
    /// stays down until the pointer moves, or a second click would pick that one.
    func releaseFilePress(at point: CGPoint, command: Bool) {
        guard let pressed = pressedFile else { return }
        pressedFile = nil
        let order = state.shelf.stack(pressed.stack)?.items.map(\.id)
        onPickFile(pressed.stack, pressed.hit, command)
        if state.shelf.stack(pressed.stack)?.items.map(\.id) != order {
            hoverHeldAt = point
            state.setHoveredFile(nil)
        }
    }
}

// MARK: - Dragging files out

extension OverlayController {
    /// The body of a stack holds all its files, front first; a tab, or the front card's top
    /// strip, holds that file alone.
    private func draggedFiles(_ press: ShelfHover, in stack: ShelfStack) -> [ShelfItem] {
        switch press.hit {
        case .body: stack.items
        case .file(let index): stack.items.indices.contains(index) ? [stack.items[index]] : []
        }
    }

    /// Past the threshold a press on a stack becomes a drag of its files, once. Files that
    /// cannot be dragged stay where they are, and the press is no longer a click.
    func continueFilePress(to point: CGPoint, event: NSEvent) {
        guard let pressed = pressedFile, let press = pressLocation,
              hypot(point.x - press.x, point.y - press.y) > Self.dragThreshold else { return }
        pressedFile = nil
        guard beginFileDrag(pressed, event: event) else { return }
        // Held, the press would keep the full-screen panel taking events, and it would swallow
        // the drop meant for the app below.
        pressLocation = nil
        refreshPointer()
    }

    private func beginFileDrag(_ press: ShelfHover, event: NSEvent) -> Bool {
        guard let view = panel?.contentView, let stack = state.shelf.stack(press.stack),
              let box = geometry.fileDragRects[press.stack] else {
            FileDragSource.log.notice("file drag not started: the stack is gone")
            return false
        }
        guard !isConverting(stack.id) else {
            FileDragSource.log.notice("file drag not started: a file of the stack is converting")
            return false
        }
        let files = draggedFiles(press, in: stack)
        let urls = files.compactMap { fileURL($0.id) }
        guard !files.isEmpty, urls.count == files.count else {
            FileDragSource.log.notice("file drag not started: a file has nothing to give")
            return false
        }
        let items = dragItems(files, urls: urls, onFrontOf: stack, in: box)
        let source = FileDragSource(
            outsideOperations: FileDragSource.outsideOperations(for: urls),
            onMoved: { [weak self] in self?.refreshPointer() },
            onEnded: { [weak self] operation in self?.fileDragEnded(operation) })
        let isWholeStack = files.count == stack.items.count
        // Before the session begins: should AppKit end it at once, the end must find what to
        // clear, or every later drop on the island would be refused as the shelf's own.
        outgoing = OutgoingFileDrag(
            ids: files.map(\.id), stack: stack.id, isWholeStack: isWholeStack, source: source)
        FileDragSource.log.notice("file drag began; files: \(files.count), whole stack: \(isWholeStack)")
        let session = view.beginDraggingSession(with: items, event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
        return true
    }

    /// Taken by another app, the files leave the shelf. Taken back by the island, cancelled or
    /// refused, they stay.
    private func fileDragEnded(_ operation: NSDragOperation) {
        guard let drag = outgoing else { return }
        outgoing = nil
        // The slot and the target go with the drag, whether or not AppKit said it left.
        state.setFileDragHovering(false)
        let leaves = operation != [] && !drag.kept
        FileDragSource.log.notice(
            "file drag ended; operation: \(operation.logName, privacy: .public), kept by the island: \(drag.kept), files leave the shelf: \(leaves)")
        if leaves { onFilesDraggedOut(drag.ids) }
        refreshPointer()
    }

    /// One item per file, front first. The images start where the front card's picture is and
    /// fan out up and to the right like the drawer's tabs; past the fifth, files ride along
    /// without one.
    private func dragItems(
        _ files: [ShelfItem], urls: [URL], onFrontOf stack: ShelfStack, in box: CGRect
    ) -> [NSDraggingItem] {
        let square = dragSquare(onFrontOf: stack, in: box)
        let drawn = 5
        let fan: CGFloat = 4
        return zip(files, urls).enumerated().map { index, file in
            let (item, url) = file
            let dragged = NSDraggingItem(pasteboardWriter: url as NSURL)
            let step = CGFloat(min(index, drawn - 1)) * fan
            let slot = square.offsetBy(dx: step, dy: -step)
            let image = index < drawn ? dragImage(item.id) : nil
            dragged.setDraggingFrame(image.map { fitted($0, in: slot) } ?? slot, contents: image)
            return dragged
        }
    }

    /// 48 × 48, centred on the front card's picture, so the files seem to lift off the card.
    private func dragSquare(onFrontOf stack: ShelfStack, in box: CGRect) -> CGRect {
        let card = StackLayout.cards(count: stack.items.count)[0]
            .offsetBy(dx: box.minX, dy: box.minY)
        let picture = CGRect(
            x: card.minX, y: card.minY, width: card.width, height: card.height - FileCard.labelHeight)
        let side: CGFloat = 48
        return CGRect(x: picture.midX - side / 2, y: picture.midY - side / 2, width: side, height: side)
    }

    /// The image as large as the square allows and not stretched, centred in it.
    private func fitted(_ image: NSImage, in square: CGRect) -> CGRect {
        let scale = square.width / max(image.size.width, image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: square.midX - size.width / 2, y: square.midY - size.height / 2,
            width: size.width, height: size.height)
    }
}

/// Files dragged out of the shelf, from the moment the drag begins until it ends.
struct OutgoingFileDrag {
    /// Front first.
    let ids: [UUID]
    /// The stack they were taken from.
    let stack: UUID
    /// They are all that stack holds: set apart among the tiles they would change nothing.
    let isWholeStack: Bool
    /// Kept for the session: AppKit does not promise to keep its source alive.
    let source: FileDragSource
    /// Where on the island a drop would put them, as of the drag's last move over it.
    var place: OwnDropPlace?
    /// The island took the drop itself: the files stay on the shelf.
    var kept = false
}

/// Where the island takes back its own dragged files.
enum OwnDropPlace: Equatable {
    /// Onto another stack, which they join in front.
    case stack(UUID)
    /// Onto the empty part of the row: each becomes a tile of its own.
    case apart

    fileprivate var logName: String {
        switch self {
        case .stack(let id): "join stack \(OverlayController.shortID(id))"
        case .apart: "set them apart"
        }
    }
}

extension ShelfDropPlace {
    fileprivate var logName: String {
        switch self {
        case .onto(let id): "onto stack \(OverlayController.shortID(id))"
        case .newStack(let id): "into new stack \(OverlayController.shortID(id))"
        }
    }
}

extension StackLayout.Hit {
    fileprivate var logName: String {
        switch self {
        case .body: "body"
        case .file(let index): "file \(index)"
        }
    }
}

extension NSDragOperation {
    /// Which operation a drag ended with, for the log.
    fileprivate var logName: String {
        switch self {
        case []: "none"
        case .copy: "copy"
        case .move: "move"
        case .link: "link"
        case .generic: "generic"
        default: "raw \(rawValue)"
        }
    }
}
