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
    public private(set) var nowPlaying: NowPlayingInfo?

    /// Whether the collapsed island shows its wings (artwork and level bars).
    /// True while something plays, and for a grace period after it pauses, so a
    /// paused player does not occupy the menu bar all day.
    public private(set) var showsWings = false

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
    public func setHovering(_ hovering: Bool) {
        guard phase == .collapsed || phase == .expanded else { return }
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

    public func setNowPlaying(_ info: NowPlayingInfo?) {
        nowPlaying = info
        if info == nil {
            showsWings = false
        } else if info?.isPlaying == true {
            showsWings = true
        }
        // Paused: keep what is shown; `pausedGraceElapsed()` hides the wings later.
    }

    /// Called `WingsTiming.pausedGrace` after a paused update; ignored if playback resumed.
    public func pausedGraceElapsed() {
        if nowPlaying?.isPlaying != true {
            showsWings = false
        }
    }
}
