import SwiftUI
import SymbiodockCore

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
/// The stepping is `FramePacer`'s, in the core package, where it is tested never to stand
/// still: a schedule that repeats a date makes SwiftUI spin on the main thread. It also
/// starts again from the present after sleep or a clock change.
struct FrameSchedule: TimelineSchedule {
    typealias Pulse = FramePacer.Pulse

    let interval: TimeInterval
    var pulse: Pulse?
    /// A paused schedule gives one date and stops: the view is drawn once.
    var paused = false

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(pacer: FramePacer(interval: interval, pulse: pulse, paused: paused, from: startDate))
    }

    struct Entries: Sequence, IteratorProtocol {
        var pacer: FramePacer

        mutating func next() -> Date? {
            pacer.next(now: Date())
        }
    }
}
