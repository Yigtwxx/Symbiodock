import CoreGraphics
import Foundation
import Observation

/// What the island is doing right now.
public enum IslandPhase: Equatable, Sendable {
    case collapsed
    case expanded
    /// Being dragged, still attached to its anchor.
    case stretching
    /// Being dragged, torn off its anchor.
    case detached
    /// Released, animating to the target anchor.
    case settling
}

/// How long the pointer must stay inside or outside before the island reacts.
public enum HoverTiming {
    public static let enterDelay: Duration = .milliseconds(80)
    public static let exitDelay: Duration = .milliseconds(250)
}

/// How long the collapsed wings stay visible after playback pauses.
public enum WingsTiming {
    public static let pausedGrace: Duration = .seconds(10)
}

/// Drag constants shared by the state and the symbiote effect, so they cannot drift apart.
public enum IslandDrag {
    /// Pointer travel (pt) since the grab beyond which the island tears off its anchor.
    public static let tearDistance: CGFloat = 120
}

/// The single source of truth for what the island is doing.
@MainActor
@Observable
public final class IslandState {
    public private(set) var phase: IslandPhase = .collapsed {
        didSet { if phase != .expanded { clearHoveredFile() } }
    }
    /// What plays, the main track first. A second slot is a second source heard at the
    /// same time; the collapsed island shows it peeking out behind the first.
    public private(set) var mediaSlots: [NowPlayingSlot] = []
    /// The main track: the one the collapsed island speaks for.
    public var nowPlaying: NowPlayingInfo? { mediaSlots.first?.info }

    private var systemPlaying: NowPlayingInfo?
    private var companionPlaying: NowPlayingInfo?
    private var otherPlaying: [NowPlayingClient] = []
    /// Second sources that stayed paused through their grace period: hidden until they play
    /// again, so a paused player does not sit behind the main track all day. More than one,
    /// because the app that takes a retired companion's place can retire in turn.
    private var retiredOrigins: Set<NowPlayingOrigin> = []

    /// How loud each player is that has a volume of its own, 0...1. A player is absent
    /// until it has been asked, and when it cannot be asked.
    public private(set) var volumes: [VolumeTarget: Double] = [:]

    /// Whether the media face is shown collapsed (artwork and level bars).
    /// True while something plays, and for a grace period after it pauses, so a
    /// paused player does not occupy the menu bar all day.
    public private(set) var mediaWings = false

    /// The agent sessions, ordered, with what deserves attention.
    public private(set) var board = AgentSessionBoard()
    /// The tabs in the order the user chose.
    public private(set) var tabOrder: [IslandTab] = TabOrder.default
    /// The tab the expanded island shows.
    public private(set) var selectedTab: IslandTab = TabOrder.default[0] {
        didSet { if selectedTab != .files { clearHoveredFile() } }
    }

    /// The files held on the shelf.
    public private(set) var shelf = FileShelf()
    /// Conversions in flight or being revealed, by item.
    public private(set) var conversions: [UUID: FileConversion] = [:]
    /// A message about one item, until the person moves on.
    public private(set) var shelfNotice: ShelfNotice?
    /// A file from another app is being dragged over the island.
    public private(set) var isFileDragHovering = false
    /// The shelf's own files are dragged over the row's empty part: a drop sets them apart.
    public private(set) var fileDragSetsApart = false
    /// What the pointer rests on in the shelf; only while the island shows the Files tab.
    public private(set) var hoveredFile: ShelfHover?
    /// The stack a dragged file would join.
    public private(set) var fileDropTarget: UUID?

    /// The count bubble right of the island: only at the notch, only collapsed, only with files.
    public var filesBubbleShown: Bool {
        anchor == .notch && phase == .collapsed && !shelf.isEmpty
    }

    /// Whether the collapsed island at the notch is widened by its wings.
    public var showsWings: Bool { mediaWings || board.hasFace }

    /// What the collapsed island shows.
    public var face: IslandFace {
        TabSelection.face(
            order: tabOrder, mediaHasFace: mediaWings, agentsHasFace: board.hasFace)
    }

    /// The tab shown in the round bubble beside the island: the one that has a face but
    /// is not the island's. Only at the notch and only while collapsed.
    public var bubbleTab: IslandTab? {
        guard anchor == .notch, phase == .collapsed else { return nil }
        return TabSelection.bubble(
            order: tabOrder, mediaHasFace: mediaWings, agentsHasFace: board.hasFace)
    }

    /// Where the island rests when it is not being dragged.
    public private(set) var anchor: IslandAnchor = .notch
    /// Pointer position (panel-local) while stretching or detached, otherwise nil.
    public private(set) var dragLocation: CGPoint?
    /// Where the island was attached when the current drag began: the root of the effect.
    public private(set) var dragOrigin: CGPoint?
    /// Pointer position (panel-local) when the current drag began.
    public private(set) var dragStart: CGPoint?

    /// Pointer travel (pt) since the grab beyond which the island tears off.
    public nonisolated static var tearDistance: CGFloat { IslandDrag.tearDistance }

    /// Pointer movement since the drag began, to be added to the island's resting frame; nil when not dragging.
    public var dragOffset: CGSize? {
        guard let dragLocation, let dragStart else { return nil }
        return CGSize(width: dragLocation.x - dragStart.x, height: dragLocation.y - dragStart.y)
    }

    public init() {}

    /// Whether the island is being dragged (stretching or detached).
    public var isDragging: Bool { phase == .stretching || phase == .detached }

    /// Called after the hover delay has elapsed, not on every pointer move.
    /// Ignored unless the island is collapsed or expanded, so a late timer cannot cancel a drag.
    /// `tab` is the tab to open on when the pointer rests on the bubble; nil lets the usual
    /// rule choose.
    public func setHovering(_ hovering: Bool, opening tab: IslandTab? = nil) {
        guard phase == .collapsed || phase == .expanded else { return }
        if hovering, phase == .collapsed {
            selectedTab = tab ?? TabSelection.tabToOpen(
                order: tabOrder, attention: board.attention,
                mediaHasContent: nowPlaying != nil, agentsHasContent: !board.rows.isEmpty,
                filesHasContent: !shelf.isEmpty)
        }
        if !hovering, phase == .expanded { leaveSelectedTab() }
        phase = hovering ? .expanded : .collapsed
    }

    /// Applies a saved anchor at launch; ignored while dragging or settling.
    public func restoreAnchor(_ anchor: IslandAnchor) {
        guard phase == .collapsed || phase == .expanded else { return }
        self.anchor = anchor
    }

    /// Starts a drag from a collapsed or expanded island; ignored otherwise.
    public func beginDrag(at point: CGPoint, from origin: CGPoint) {
        guard phase == .collapsed || phase == .expanded else { return }
        if phase == .expanded { leaveSelectedTab() }
        phase = .stretching
        dragOrigin = origin
        dragStart = point
        dragLocation = point
    }

    /// Moves the drag. Returns true exactly once per drag: on the update that tears the island off.
    /// The caller must then call `SymbioteSimulation.tear()` so the effect breaks on the same update.
    @discardableResult
    public func drag(to point: CGPoint) -> Bool {
        guard isDragging, let dragStart else { return false }
        dragLocation = point
        guard phase == .stretching else { return false }
        // Measured from the grab point, not the attachment: grabbing far from the
        // attachment must not tear on the first point of movement.
        let distance = hypot(point.x - dragStart.x, point.y - dragStart.y)
        guard distance > Self.tearDistance else { return false }
        phase = .detached
        return true
    }

    /// Releases the drag. Only a torn-off island moves to `resolvedAnchor`.
    public func endDrag(resolvedAnchor: IslandAnchor) {
        guard isDragging else { return }
        if phase == .detached { anchor = resolvedAnchor }
        phase = .settling
        dragLocation = nil
        dragStart = nil
        dragOrigin = nil
    }

    /// Abandons a drag (focus lost, display change): back to collapsed at the current anchor.
    /// Ignored while collapsed or expanded.
    public func cancelDrag() {
        guard isDragging || phase == .settling else { return }
        phase = .collapsed
        dragLocation = nil
        dragStart = nil
        dragOrigin = nil
    }

    /// Called when the settle animation is done; the island is then collapsed.
    public func finishSettling() {
        guard phase == .settling else { return }
        phase = .collapsed
    }

    /// The system-wide source reported.
    public func setNowPlaying(_ info: NowPlayingInfo?) {
        systemPlaying = info
        mediaChanged(.system, info)
    }

    /// The player that is asked directly reported.
    public func setCompanionPlaying(_ info: NowPlayingInfo?) {
        companionPlaying = info
        mediaChanged(.companion, info)
    }

    /// The system listed every app that plays, the one it elects included. A listed app that
    /// is shown and pauses keeps its slot until the second-slot grace hides it.
    public func setOtherPlaying(_ clients: [NowPlayingClient]) {
        otherPlaying = clients
        // Playing again, or gone: either way it is no longer the paused app that was hidden.
        let stillRetired = retiredOrigins.filter { origin in
            guard let pid = origin.clientPID else { return true }
            return clients.first(where: { $0.pid == pid })?.info.isPlaying == false
        }
        if stillRetired != retiredOrigins { retiredOrigins = stillRetired }
        refreshMediaSlots()
    }

    private func mediaChanged(_ origin: NowPlayingOrigin, _ info: NowPlayingInfo?) {
        // Playing again, or gone: either way it is no longer the paused track that was hidden.
        if info?.isPlaying != false, retiredOrigins.contains(origin) {
            retiredOrigins.remove(origin)
        }
        refreshMediaSlots()
    }

    private func refreshMediaSlots() {
        var slots = lineup()
        // Only a second slot retires; alone, a paused track stays for the open island.
        if slots.count == 2, retiredOrigins.contains(slots[1].origin) { slots.removeLast() }
        // Assign only on change: every assignment redraws the island.
        if slots != mediaSlots { mediaSlots = slots }
        if let front = slots.first {
            if front.info.isPlaying, !mediaWings { mediaWings = true }
        } else if mediaWings {
            mediaWings = false
        }
        // Paused: keep what is shown; `pausedGraceElapsed()` hides the wings later.
    }

    /// What plays, with a retired system source, companion or listed app left out before the
    /// places are filled, so its place goes to an app that plays. Alone it is still shown,
    /// like any retired track.
    private func lineup() -> [NowPlayingSlot] {
        // A retired app no longer keeps its place just because it holds one.
        let shownClients = Set(mediaSlots.compactMap(\.origin.clientPID))
            .subtracting(retiredOrigins.compactMap(\.clientPID))
        let all = NowPlayingLineup.slots(
            system: systemPlaying, companion: companionPlaying, others: otherPlaying,
            shownClients: shownClients)
        let retired = [
            retiredOrigins.contains(.system) ? systemPlaying : nil,
            retiredOrigins.contains(.companion) ? companionPlaying : nil,
        ].compactMap { $0 }
        guard !retired.isEmpty else { return all }
        // The retired app's other entries go too: Music is often the system source and the
        // companion at once, and its own entry in the list is not another app.
        func isRetired(_ info: NowPlayingInfo) -> Bool {
            retired.contains { NowPlayingLineup.isSameSource($0, info) }
        }
        let system = systemPlaying.flatMap { isRetired($0) ? nil : $0 }
        let companion = companionPlaying.flatMap { isRetired($0) ? nil : $0 }
        let others = otherPlaying.filter { !isRetired($0.info) }
        let withoutRetired = NowPlayingLineup.slots(
            system: system, companion: companion, others: others, shownClients: shownClients)
        return withoutRetired.isEmpty ? all : withoutRetired
    }

    /// Called `WingsTiming.pausedGrace` after a paused update; ignored if playback resumed.
    public func pausedGraceElapsed() {
        if nowPlaying?.isPlaying != true {
            mediaWings = false
        }
        if mediaSlots.count == 2, !mediaSlots[1].info.isPlaying {
            retiredOrigins.insert(mediaSlots[1].origin)
            refreshMediaSlots()
        }
    }

    /// A player reported its volume, or the user set it; nil when it cannot be asked.
    public func setVolume(_ fraction: Double?, for target: VolumeTarget) {
        let value = fraction.map { VolumeLevel.fraction(percent: VolumeLevel.percent($0)) }
        // Assign only on change: every assignment redraws the island.
        if volumes[target] != value { volumes[target] = value }
    }

    public func setAgentSessions(_ sessions: [AgentSession]) {
        var next = board
        next.update(sessions)
        // Assign only on change: every assignment redraws the island.
        if next != board { board = next }
    }

    /// The seal of a finished session has played: it stops leading the collapsed island.
    public func settleFinished(_ id: String) {
        var next = board
        next.settle(id)
        // Assign only on change: every assignment redraws the island.
        if next != board { board = next }
    }

    /// The finished session whose seal the collapsed island plays, if any: while the island
    /// is collapsed and a finish is the most urgent thing it shows. On the media face the
    /// seal is the mark's check alone.
    public var sealingID: String? {
        guard phase == .collapsed, board.attention == .finished else { return nil }
        return board.attentionRow?.id
    }

    /// Whether the collapsed island draws the dashed compacting line around itself: the
    /// session the agents face speaks for is compacting.
    public var showsCompactingRim: Bool {
        phase == .collapsed && face == .agents && board.lead?.state == .compacting
    }

    /// Applies a tab order, repaired if it is damaged. A collapsed island will open on it.
    public func setTabOrder(_ order: [IslandTab]) {
        let repaired = TabOrder.repaired(TabOrder.encode(order))
        // Assign only on change: every assignment redraws the island.
        if repaired != tabOrder { tabOrder = repaired }
    }

    /// A click on a tab.
    public func selectTab(_ tab: IslandTab) {
        guard tab != selectedTab else { return }
        leaveSelectedTab()
        selectedTab = tab
    }

    // MARK: Files shelf

    /// Puts back the files saved at launch.
    public func restoreShelf(_ items: [ShelfItem]) {
        setShelf(FileShelf(items: items))
    }

    /// Dropped files: several form one new stack; with `stack`, they join it in front.
    public func addShelfItems(_ items: [ShelfItem], onto stack: UUID? = nil) {
        var next = shelf
        next.add(items, onto: stack)
        setShelf(next)
    }

    /// Files of one drop arriving one by one: together they make the stack `stack`, in the
    /// order they arrive (see `FileShelf.add(_:into:)`).
    public func addShelfItems(_ items: [ShelfItem], into stack: UUID) {
        var next = shelf
        next.add(items, into: stack)
        setShelf(next)
    }

    /// A tile dropped on a stack: the files go in front of it.
    public func moveShelfItems(_ ids: [UUID], onto stack: UUID) {
        var next = shelf
        next.move(ids, onto: stack)
        setShelf(next)
    }

    /// Each file leaves its stack and becomes a lone tile.
    public func separateShelfItems(_ ids: [UUID]) {
        var next = shelf
        next.separate(ids)
        setShelf(next)
    }

    public func bringShelfItemToFront(_ id: UUID) {
        var next = shelf
        next.bringToFront(id)
        setShelf(next)
    }

    /// A notice about another file goes away with the look at these.
    public func selectShelfItems(_ ids: [UUID]) {
        var next = shelf
        next.select(ids)
        setShelf(next)
        dropNoticeOutsideSelection()
    }

    public func toggleShelfItems(_ ids: [UUID]) {
        var next = shelf
        next.toggle(ids)
        setShelf(next)
        dropNoticeOutsideSelection()
    }

    /// Takes the files off the shelf and drops whatever hung on them.
    public func removeShelfItems(_ ids: [UUID]) {
        var next = shelf
        next.remove(ids)
        setShelf(next)
    }

    public func setShelfNotice(_ notice: ShelfNotice?) {
        if notice != shelfNotice { shelfNotice = notice }
    }

    /// Empties the shelf and drops every conversion and notice.
    public func clearShelf() {
        setShelf(FileShelf())
    }

    /// The pointer rests on a stack of the shelf (or on none).
    public func setHoveredFile(_ hover: ShelfHover?) {
        if hover != hoveredFile { hoveredFile = hover }
    }

    /// A dragged file is over a stack, which it would join.
    public func setFileDropTarget(_ stack: UUID?) {
        if stack != fileDropTarget { fileDropTarget = stack }
    }

    /// The shelf's own files are dragged over the empty part of the row, where a drop sets
    /// them apart. The row shows it without making room: no stack moves under the pointer.
    public func setFileDragSetsApart(_ setsApart: Bool) {
        if setsApart != fileDragSetsApart { fileDragSetsApart = setsApart }
    }

    /// A file drag from another app is over the island: it opens on Files at once (or
    /// switches to it), and the row makes room for the drop. When any file drag ends, no stack
    /// is its target any more and nothing is shown as set apart.
    public func setFileDragHovering(_ hovering: Bool) {
        guard hovering else {
            if isFileDragHovering { isFileDragHovering = false }
            setFileDropTarget(nil)
            setFileDragSetsApart(false)
            return
        }
        guard phase == .collapsed || phase == .expanded else { return }
        if !isFileDragHovering { isFileDragHovering = true }
        openOnFiles()
    }

    /// Opens the island on Files, or switches the open island to it; ignored while the island
    /// is dragged or settling. A file drag on its way in does this without the hover delay.
    public func openOnFiles() {
        switch phase {
        case .collapsed: setHovering(true, opening: .files)
        case .expanded: selectTab(.files)
        case .stretching, .detached, .settling: break
        }
    }

    /// Starts the conversion of one file; ignored when it is not on the shelf or already busy.
    public func beginConversion(_ id: UUID, label: String, at date: Date) {
        guard conversions[id] == nil, shelf.items.contains(where: { $0.id == id }) else { return }
        conversions[id] = FileConversion(label: label, started: date)
        if shelfNotice?.id == id { shelfNotice = nil }
    }

    /// The cocoon is closed and the work is over: the tile changes under it and the reveal starts.
    public func revealConversion(_ id: UUID, result: ConversionResult, at date: Date) {
        guard var conversion = conversions[id], conversion.revealStarted == nil else { return }
        switch result {
        case .converted(let url, let isDirectory):
            var next = shelf
            next.replace(id, url: url, isDirectory: isDirectory)
            setShelf(next)
        case .failed(let text):
            setShelfNotice(ShelfNotice(id: id, text: text))
        case .cancelled:
            break
        }
        conversion.revealStarted = date
        conversions[id] = conversion
    }

    /// The reveal is over: the file is an ordinary tile again.
    public func endConversion(_ id: UUID) {
        if conversions[id] != nil { conversions[id] = nil }
    }

    /// Assign only on change: every assignment redraws the island. What hung on a file that
    /// is gone (its conversion, its notice) goes with it, and so do a hover or drop target
    /// naming a stack that is gone.
    private func setShelf(_ next: FileShelf) {
        guard next != shelf else { return }
        let kept = Set(next.items.map(\.id))
        let gone = shelf.items.map(\.id).filter { !kept.contains($0) }
        shelf = next
        for id in gone where conversions[id] != nil { conversions[id] = nil }
        if let notice = shelfNotice, gone.contains(notice.id) { shelfNotice = nil }
        let stacks = Set(next.items.map(\.stack))
        if let hover = hoveredFile, !stacks.contains(hover.stack) { hoveredFile = nil }
        if let target = fileDropTarget, !stacks.contains(target) { fileDropTarget = nil }
    }

    private func dropNoticeOutsideSelection() {
        if let notice = shelfNotice, !shelf.selection.contains(notice.id) { shelfNotice = nil }
    }

    private func clearHoveredFile() {
        if hoveredFile != nil { hoveredFile = nil }
    }

    /// Once the Agents tab has been looked at, what finished is no longer news.
    private func leaveSelectedTab() {
        guard selectedTab == .agents else { return }
        var next = board
        next.markSeen()
        if next != board { board = next }
    }
}
