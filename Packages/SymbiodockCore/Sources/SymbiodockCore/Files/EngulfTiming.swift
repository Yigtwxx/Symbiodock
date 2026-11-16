import Foundation

/// Where a converting tile's goo is: closing over the tile, closed, or opening again.
public enum EngulfPhase: Equatable, Sendable {
    /// 0...1: strands reach in from the tile's edges and close over it.
    case engulf(Double)
    /// Fully black, waiting for the conversion to finish.
    case cocoon
    /// 0...1: the cover splits in the middle and pulls back to the edges.
    case reveal(Double)
    /// Nothing left to draw.
    case done
}

/// The clock of the engulf effect that hides a file tile while it converts. Pure functions of
/// time, so the view only draws. Spec: `2026-11-16-files-tab-design.md`, "Venom sarma efekti".
public enum EngulfTiming {
    /// The strands closing over the tile.
    public static let engulf: TimeInterval = 0.7
    /// The cocoon stays closed at least this long, so a quick conversion still reads as one.
    public static let minimumHold: TimeInterval = 0.25
    /// The cover opening again.
    public static let reveal: TimeInterval = 0.6
    /// With Reduce Motion the tile only darkens and clears, this long each way.
    public static let stillFade: TimeInterval = 0.2

    /// How long the work, done `elapsed` after the start, still waits before the reveal:
    /// the cocoon must have closed and held for `minimumHold`.
    public static func revealDelay(elapsed: TimeInterval) -> TimeInterval {
        max(0, engulf + minimumHold - elapsed)
    }

    /// The phase `elapsed` after the start; `revealElapsed` is the time since the reveal began,
    /// nil while it has not.
    public static func phase(elapsed: TimeInterval, revealElapsed: TimeInterval?) -> EngulfPhase {
        if let revealElapsed {
            return revealElapsed >= reveal ? .done : .reveal(max(revealElapsed, 0) / reveal)
        }
        return elapsed >= engulf ? .cocoon : .engulf(max(elapsed, 0) / engulf)
    }
}
