import Foundation
import Testing
@testable import SymbiodockCore

struct EngulfTimingTests {
    @Test func theRevealWaitsForTheCocoonToClose() {
        #expect(EngulfTiming.revealDelay(elapsed: 0.1) == 0.85)
        #expect(EngulfTiming.revealDelay(elapsed: 0.95) == 0)
        #expect(EngulfTiming.revealDelay(elapsed: 5) == 0)
    }

    @Test func phasesFollowTheClock() {
        #expect(EngulfTiming.phase(elapsed: -1, revealElapsed: nil) == .engulf(0))
        #expect(EngulfTiming.phase(elapsed: 0.35, revealElapsed: nil) == .engulf(0.5))
        #expect(EngulfTiming.phase(elapsed: 0.7, revealElapsed: nil) == .cocoon)
        #expect(EngulfTiming.phase(elapsed: 30, revealElapsed: nil) == .cocoon)
        #expect(EngulfTiming.phase(elapsed: 2, revealElapsed: 0.3) == .reveal(0.5))
        #expect(EngulfTiming.phase(elapsed: 2, revealElapsed: 0.6) == .done)
    }

    @Test func aStackIsOneCocoonThatOpensWhenItsLastFileIsDone() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let early = FileConversion(label: "PDF", started: start)
        let late = FileConversion(label: "PDF", started: start.addingTimeInterval(0.4))
        #expect(EngulfTiming.cocoon(of: []) == nil)
        #expect(EngulfTiming.cocoon(of: [late, early])?.started == start)
        // One file still converting keeps the whole stack closed.
        let doneEarly = FileConversion(
            label: "PDF", started: start, revealStarted: start.addingTimeInterval(1))
        #expect(EngulfTiming.cocoon(of: [late, doneEarly])?.revealStarted == nil)
        let doneLate = FileConversion(
            label: "PDF", started: late.started, revealStarted: start.addingTimeInterval(2))
        let both = EngulfTiming.cocoon(of: [doneEarly, doneLate])
        #expect(both?.started == start)
        #expect(both?.revealStarted == start.addingTimeInterval(2))
    }
}
