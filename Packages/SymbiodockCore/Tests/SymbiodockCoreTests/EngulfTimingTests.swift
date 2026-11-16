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
}
