import Observation

public enum IslandPhase: Equatable, Sendable {
    case collapsed
    case expanded
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

    public init() {}

    /// Called after the hover delay has elapsed, not on every pointer move.
    public func setHovering(_ hovering: Bool) {
        phase = hovering ? .expanded : .collapsed
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
