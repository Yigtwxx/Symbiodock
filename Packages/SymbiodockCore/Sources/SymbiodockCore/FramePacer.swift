import Foundation

/// Decides when an animation is drawn next. A view that asks "when is my next frame?"
/// in a loop must always get a later moment back; an answer that does not move on would
/// spin the main thread forever. So every step here moves on by at least `smallestStep`,
/// whatever it is given.
public struct FramePacer: Sendable {
    /// A motion that repeats: it lasts `length` seconds at the start of every `period`,
    /// counted from `anchor`. Frames are drawn only while it lasts, and once at its end,
    /// so that the view comes to rest.
    public struct Pulse: Equatable, Sendable {
        public let anchor: Date
        public let period: TimeInterval
        public let length: TimeInterval

        public init(anchor: Date, period: TimeInterval, length: TimeInterval) {
            self.anchor = anchor
            self.period = period
            self.length = length
        }

        /// A pulse that cannot be paced: no time, no period, or nothing to count from.
        var isUsable: Bool {
            period.isFinite && period > FramePacer.smallestStep && length.isFinite && length >= 0
                && anchor.timeIntervalSinceReferenceDate.isFinite
        }
    }

    /// No two frames are closer together than this.
    public static let smallestStep: TimeInterval = 0.001

    private let interval: TimeInterval
    private let pulse: Pulse?
    private let paused: Bool
    private var upcoming: Date
    private var started = false

    /// - Parameters:
    ///   - interval: seconds between frames; anything unusable counts as one second.
    ///   - pulse: draw only during this repeating motion; an unusable pulse is ignored.
    ///   - paused: give one frame and stop, so the view is drawn once.
    ///   - start: the first frame.
    public init(interval: TimeInterval, pulse: Pulse? = nil, paused: Bool = false, from start: Date) {
        self.interval = interval.isFinite ? max(interval, Self.smallestStep) : 1
        self.pulse = pulse.flatMap { $0.isUsable ? $0 : nil }
        self.paused = paused
        upcoming = start
    }

    /// The next frame, with the present moment known. After the Mac slept the frames it
    /// would give lie far in the past, and after the clock was set back they lie in the
    /// future; either way it starts again from `now` instead of walking through them (or
    /// waiting for them). Otherwise it is `next()`.
    public mutating func next(now: Date) -> Date? {
        let present = now.timeIntervalSinceReferenceDate
        if !(started && paused), present.isFinite, upcoming.timeIntervalSinceReferenceDate.isFinite {
            let longestWait = max(interval, pulse?.period ?? 0)
            let lateness = present - upcoming.timeIntervalSinceReferenceDate
            if lateness > Self.tolerance || -lateness > Self.tolerance + longestWait {
                upcoming = now
            }
        }
        return next()
    }

    /// How far a frame may lie behind or ahead of the present before it counts as stale.
    private static let tolerance: TimeInterval = 1

    /// The next frame; nil when there are no more.
    public mutating func next() -> Date? {
        if started, paused { return nil }
        guard upcoming.timeIntervalSinceReferenceDate.isFinite else { return nil }
        started = true
        let current = upcoming
        var following = current.addingTimeInterval(interval)
        if let pulse {
            var phase = current.timeIntervalSince(pulse.anchor).truncatingRemainder(dividingBy: pulse.period)
            if phase < 0 { phase += pulse.period }
            // A moment a hair before a beat belongs to that beat; otherwise the next beat
            // would round back to this very moment.
            if pulse.period - phase < Self.smallestStep { phase = 0 }
            let beatStart = current.addingTimeInterval(-phase)
            if phase < pulse.length - Self.smallestStep {
                // Inside the motion: the next frame, but no later than its end.
                following = min(following, beatStart.addingTimeInterval(pulse.length))
            } else {
                following = beatStart.addingTimeInterval(pulse.period)
            }
        }
        // Whatever the arithmetic above gave, time moves on.
        let earliest = current.addingTimeInterval(Self.smallestStep)
        upcoming = following >= earliest ? following : earliest
        return current
    }
}
