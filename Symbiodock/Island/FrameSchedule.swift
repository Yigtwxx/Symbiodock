import SwiftUI

// How the island's animations are paced.
//
// Measured on the always-on island: while a view redraws more often than about every
// 0.35 s, SwiftUI keeps the full-screen panel's update cycle running at the screen's rate,
// and that alone costs about 5 % of a core, whatever the view draws (an empty `Canvas`
// costs the same). Redrawing every 0.4 s or less often costs nothing measurable. So:
// motion that is slow enough for a few frames a second uses `FrameSchedule`; short
// motions that repeat with rests between use `FrameSchedule` with a `Pulse`, which draws
// only while the motion lasts; and motion that has to be smooth and never rests is handed to Core
// Animation (see `SpinningArc`, `Breathing`), which runs in the render server and costs
// the app nothing.

/// Draws a `TimelineView` from a timer, `interval` seconds apart. With a `pulse` it draws
/// only while the motion lasts and once more at its end, so that the view comes to rest.
struct FrameSchedule: TimelineSchedule {
    /// A motion that repeats: it lasts `length` seconds at the start of every `period`,
    /// counted from `anchor`.
    struct Pulse {
        let anchor: Date
        let period: TimeInterval
        let length: TimeInterval
    }

    let interval: TimeInterval
    var pulse: Pulse?
    /// A paused schedule gives one date and stops: the view is drawn once.
    var paused = false

    func entries(from startDate: Date, mode: Mode) -> Entries {
        return Entries(schedule: self, upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let schedule: FrameSchedule
        var upcoming: Date
        var started = false

        mutating func next() -> Date? {
            if started, schedule.paused { return nil }
            started = true
            let current = upcoming
            // Every step moves on by at least a millisecond, whatever the arithmetic says:
            // a step of zero would make SwiftUI walk the sequence forever.
            let following = current.addingTimeInterval(Swift.max(schedule.interval, 0.001))
            guard let pulse = schedule.pulse else {
                upcoming = following
                return current
            }
            var phase = current.timeIntervalSince(pulse.anchor).truncatingRemainder(dividingBy: pulse.period)
            if phase < 0 { phase += pulse.period }
            // A date that falls a hair before a beat belongs to that beat; otherwise the
            // next beat would round to this very date and the loop would never move on.
            if pulse.period - phase < 0.001 { phase = 0 }
            let beatStart = current.addingTimeInterval(-phase)
            if phase < pulse.length - 0.001 {
                // Inside the motion: the next frame, but no later than its end.
                let end = beatStart.addingTimeInterval(pulse.length)
                upcoming = following < end ? following : end
            } else {
                upcoming = beatStart.addingTimeInterval(pulse.period)
            }
            if !(upcoming >= current.addingTimeInterval(0.001)) {
                upcoming = current.addingTimeInterval(0.001)
            }
            return current
        }
    }
}
