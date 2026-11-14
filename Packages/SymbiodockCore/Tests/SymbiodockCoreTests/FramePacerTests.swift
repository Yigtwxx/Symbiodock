import Foundation
import Testing
@testable import SymbiodockCore

struct FramePacerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000.25)

    /// The first `count` frames of a pacer.
    private func frames(_ pacer: FramePacer, count: Int) -> [Date] {
        var pacer = pacer
        var frames: [Date] = []
        while frames.count < count, let frame = pacer.next() { frames.append(frame) }
        return frames
    }

    /// Whether every frame is later than the one before by at least the smallest step.
    private func movesOn(_ frames: [Date]) -> Bool {
        zip(frames, frames.dropFirst()).allSatisfy {
            $1.timeIntervalSince($0) >= FramePacer.smallestStep * 0.99
        }
    }

    @Test func framesAreAnIntervalApart() {
        let frames = frames(FramePacer(interval: 0.4, from: start), count: 4)
        #expect(frames.first == start)
        #expect(frames.count == 4)
        for (earlier, later) in zip(frames, frames.dropFirst()) {
            #expect(abs(later.timeIntervalSince(earlier) - 0.4) < 1e-6)
        }
    }

    @Test func aPausedPacerGivesOneFrame() {
        var pacer = FramePacer(interval: 0.05, paused: true, from: start)
        #expect(pacer.next() == start)
        #expect(pacer.next() == nil)
        #expect(pacer.next() == nil)
    }

    @Test func anUnusableIntervalStillMovesOn() {
        for interval in [0, -1, -0.0, 1e-12, Double.nan, .infinity, -.infinity] {
            let frames = frames(FramePacer(interval: interval, from: start), count: 500)
            #expect(frames.count == 500, "\(interval)")
            #expect(movesOn(frames), "\(interval)")
        }
    }

    @Test func aPulseDrawsOnlyWhileTheMotionLasts() {
        let pulse = FramePacer.Pulse(anchor: start, period: 2.4, length: 0.65)
        let frames = frames(FramePacer(interval: 0.05, pulse: pulse, from: start), count: 60)
        #expect(movesOn(frames))
        for frame in frames {
            let phase = frame.timeIntervalSince(start).truncatingRemainder(dividingBy: 2.4)
            // Inside the motion, or the one frame at its end.
            #expect(phase <= 0.65 + 1e-6 || 2.4 - phase < 1e-6, "\(phase)")
        }
        // Thirteen steps and the frame at the end, per beat: not one frame every interval.
        let firstBeat = frames.filter { $0.timeIntervalSince(start) < 2.4 - 1e-6 }
        #expect(firstBeat.count <= 15)
        #expect(frames.last.map { $0.timeIntervalSince(start) > 7 } ?? false)
    }

    @Test func aPacerStartedBetweenTwoBeatsWaitsForTheNext() {
        let pulse = FramePacer.Pulse(anchor: start, period: 2.4, length: 0.6)
        let frames = frames(
            FramePacer(interval: 0.05, pulse: pulse, from: start.addingTimeInterval(1)), count: 3)
        #expect(frames[0] == start.addingTimeInterval(1))
        #expect(abs(frames[1].timeIntervalSince(start) - 2.4) < 1e-6)
        #expect(abs(frames[2].timeIntervalSince(start) - 2.45) < 1e-6)
    }

    @Test func anUnusablePulseIsIgnored() {
        let broken: [FramePacer.Pulse] = [
            .init(anchor: start, period: 0, length: 1),
            .init(anchor: start, period: -3, length: 1),
            .init(anchor: start, period: .nan, length: 1),
            .init(anchor: start, period: 2, length: .nan),
            .init(anchor: start, period: 2, length: -1),
            .init(anchor: start, period: .infinity, length: 1),
            .init(anchor: Date(timeIntervalSinceReferenceDate: .nan), period: 2, length: 1),
        ]
        for pulse in broken {
            let frames = frames(FramePacer(interval: 0.1, pulse: pulse, from: start), count: 50)
            #expect(frames.count == 50)
            #expect(movesOn(frames))
            #expect(abs(frames[1].timeIntervalSince(frames[0]) - 0.1) < 1e-6)
        }
    }

    @Test func aStartThatIsNoMomentGivesNoFrames() {
        var pacer = FramePacer(interval: 0.1, from: Date(timeIntervalSinceReferenceDate: .nan))
        #expect(pacer.next() == nil)
    }

    @Test func noSettingMakesItStandStill() {
        // A fixed sequence of pseudo-random settings, so a failure can be repeated.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random(_ range: ClosedRange<Double>) -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double(seed >> 11) / Double(1 << 53)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
        for _ in 0..<300 {
            let period = random(0.002...5)
            let pulse = FramePacer.Pulse(
                anchor: start.addingTimeInterval(random(-1000...1000)), period: period,
                length: random(0...(period * 1.5)))
            let pacer = FramePacer(
                interval: random(-0.01...0.5), pulse: random(0...1) < 0.8 ? pulse : nil,
                from: start.addingTimeInterval(random(-10...10)))
            let frames = frames(pacer, count: 400)
            #expect(frames.count == 400)
            #expect(movesOn(frames))
        }
    }

    // MARK: starting again from now

    @Test func aPacerFarBehindNowRecoversInOneStep() {
        var pacer = FramePacer(interval: 0.4, from: start)
        let now = start.addingTimeInterval(6 * 3600)
        let frame = pacer.next(now: now)
        #expect(frame == now)
        let following = pacer.next(now: now.addingTimeInterval(0.4))
        #expect(following.map { abs($0.timeIntervalSince(now) - 0.4) < 1e-6 } ?? false)
    }

    @Test func aPacerFarAheadOfNowRecovers() {
        // The clock was set back an hour.
        var pacer = FramePacer(interval: 0.4, from: start.addingTimeInterval(3600))
        let frame = pacer.next(now: start)
        #expect(frame == start)
        let pulse = FramePacer.Pulse(anchor: start, period: 2.4, length: 0.6)
        var pulsed = FramePacer(interval: 0.1, pulse: pulse, from: start.addingTimeInterval(3600))
        #expect(pulsed.next(now: start) == start)
    }

    @Test func steppingWithNowIsUnchangedWhenOnTime() {
        let pulse = FramePacer.Pulse(anchor: start, period: 2.4, length: 0.65)
        for pulse in [nil, pulse] {
            var plain = FramePacer(interval: 0.05, pulse: pulse, from: start)
            var timed = FramePacer(interval: 0.05, pulse: pulse, from: start)
            for _ in 0..<80 {
                let expected = plain.next()
                // Asked a little late, as a real view is.
                let given = timed.next(now: (expected ?? start).addingTimeInterval(0.02))
                #expect(given == expected)
            }
        }
    }

    @Test func aPausedPacerStillGivesOneFrameWithNow() {
        var pacer = FramePacer(interval: 0.05, paused: true, from: start)
        #expect(pacer.next(now: start) != nil)
        #expect(pacer.next(now: start) == nil)
    }

    @Test func pulsesAnchoredAtReferenceZeroNeverStandStill() {
        let anchor = Date(timeIntervalSinceReferenceDate: 0)
        for period in [2.4, 3.6] {
            for length in [0.3, 0.65, 1.2, period] {
                let pulse = FramePacer.Pulse(anchor: anchor, period: period, length: length)
                let beat = (820_000_000 / period).rounded() * period
                for offset in [-1e-7, 0, 1e-7, 0.3, length, -0.01] {
                    let from = Date(timeIntervalSinceReferenceDate: beat + offset)
                    let frames = frames(FramePacer(interval: 0.05, pulse: pulse, from: from), count: 2000)
                    #expect(frames.count == 2000, "\(period) \(length) \(offset)")
                    #expect(movesOn(frames), "\(period) \(length) \(offset)")
                    #expect(Set(frames.map(\.timeIntervalSinceReferenceDate)).count == 2000)
                }
            }
        }
    }
}
