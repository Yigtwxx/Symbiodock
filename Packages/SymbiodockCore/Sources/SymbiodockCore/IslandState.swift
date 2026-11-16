import CoreGraphics
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
    public private(set) var phase: IslandPhase = .collapsed
    /// What plays, the main track first. A second slot is a second source heard at the
    /// same time; the collapsed island shows it peeking out behind the first.
    public private(set) var mediaSlots: [NowPlayingSlot] = []
    /// The main track: the one the collapsed island speaks for.
    public var nowPlaying: NowPlayingInfo? { mediaSlots.first?.info }

    private var systemPlaying: NowPlayingInfo?
    private var companionPlaying: NowPlayingInfo?
    /// A second source that stayed paused through its grace period: hidden until it plays
    /// again, so a paused player does not sit behind the main track all day.
    private var retiredOrigin: NowPlayingOrigin?

    /// Whether the media face is shown collapsed (artwork and level bars).
    /// True while something plays, and for a grace period after it pauses, so a
    /// paused player does not occupy the menu bar all day.
    public private(set) var mediaWings = false

    /// The agent sessions, ordered, with what deserves attention.
    public private(set) var board = AgentSessionBoard()
    /// The tabs in the order the user chose.
    public private(set) var tabOrder: [IslandTab] = TabOrder.default
    /// The tab the expanded island shows.
    public private(set) var selectedTab: IslandTab = TabOrder.default[0]

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
                mediaHasContent: nowPlaying != nil, agentsHasContent: !board.rows.isEmpty)
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

    private func mediaChanged(_ origin: NowPlayingOrigin, _ info: NowPlayingInfo?) {
        // Playing again, or gone: either way it is no longer the paused track that was hidden.
        if retiredOrigin == origin, info?.isPlaying != false { retiredOrigin = nil }
        refreshMediaSlots()
    }

    private func refreshMediaSlots() {
        var slots = NowPlayingLineup.slots(system: systemPlaying, companion: companionPlaying)
        // Only a second slot retires; alone, a paused track stays for the open island.
        if slots.count == 2, slots[1].origin == retiredOrigin { slots.removeLast() }
        // Assign only on change: every assignment redraws the island.
        if slots != mediaSlots { mediaSlots = slots }
        if let front = slots.first {
            if front.info.isPlaying, !mediaWings { mediaWings = true }
        } else if mediaWings {
            mediaWings = false
        }
        // Paused: keep what is shown; `pausedGraceElapsed()` hides the wings later.
    }

    /// Called `WingsTiming.pausedGrace` after a paused update; ignored if playback resumed.
    public func pausedGraceElapsed() {
        if nowPlaying?.isPlaying != true {
            mediaWings = false
        }
        if mediaSlots.count == 2, !mediaSlots[1].info.isPlaying {
            retiredOrigin = mediaSlots[1].origin
            refreshMediaSlots()
        }
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

    /// Once the Agents tab has been looked at, what finished is no longer news.
    private func leaveSelectedTab() {
        guard selectedTab == .agents else { return }
        var next = board
        next.markSeen()
        if next != board { board = next }
    }
}
