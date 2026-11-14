import Foundation
import Testing
@testable import SymbiodockCore

struct MarkMotionTests {
    @Test func theDotKnocksTwiceThenRests() {
        #expect(AgentMarkMotion.dotScale(atBeat: 0) == 1)
        let peak = 1 + AgentMarkMotion.knockGrowth
        #expect(abs(AgentMarkMotion.dotScale(atBeat: 0.15) - peak) < 1e-9)
        #expect(abs(AgentMarkMotion.dotScale(atBeat: 0.45) - peak) < 1e-9)
        #expect(abs(AgentMarkMotion.dotScale(atBeat: 0.3) - 1) < 1e-9)
        #expect(AgentMarkMotion.dotScale(atBeat: 0.6) == 1)
        #expect(AgentMarkMotion.dotScale(atBeat: 1.5) == 1)
        #expect(AgentMarkMotion.dotScale(atBeat: -0.1) == 1)
    }

    @Test func aRingGoesOutOnceAndIsGone() {
        #expect(AgentMarkMotion.ripple(atBeat: -0.01, from: 0) == nil)
        #expect(AgentMarkMotion.ripple(atBeat: 0, from: 0) == 0)
        let middle = AgentMarkMotion.ripple(atBeat: 0.45, from: 0)
        #expect(middle != nil && abs(middle! - 0.5) < 1e-9)
        #expect(AgentMarkMotion.ripple(atBeat: AgentMarkMotion.rippleLength + 0.001, from: 0) == nil)
    }

    @Test func theSecondRingFollowsTheSecondKnock() {
        let start = AgentMarkMotion.knockLength
        #expect(AgentMarkMotion.ripple(atBeat: start - 0.01, from: start) == nil)
        #expect(AgentMarkMotion.ripple(atBeat: start, from: start) == 0)
        #expect(AgentMarkMotion.ripple(atBeat: start + AgentMarkMotion.rippleLength + 0.001, from: start) == nil)
    }

    @Test func theMotionRestsBeforeTheNextBeat() {
        let end = AgentMarkMotion.knockLength + AgentMarkMotion.rippleLength
        #expect(end < AgentMarkMotion.knockPeriod)
    }
}
