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

/// The single source of truth for what the island is doing.
@MainActor
@Observable
public final class IslandState {
    public private(set) var phase: IslandPhase = .collapsed

    public init() {}

    /// Called after the hover delay has elapsed, not on every pointer move.
    public func setHovering(_ hovering: Bool) {
        phase = hovering ? .expanded : .collapsed
    }
}
