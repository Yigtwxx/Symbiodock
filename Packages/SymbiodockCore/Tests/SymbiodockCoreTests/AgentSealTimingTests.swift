import Foundation
import Testing
@testable import SymbiodockCore

struct AgentSealTimingTests {
    @Test func thePhasesFitTheDuration() {
        #expect(0 < AgentSealTiming.framed)
        #expect(AgentSealTiming.framed < AgentSealTiming.rounded)
        #expect(AgentSealTiming.rounded < AgentSealTiming.checked)
        #expect(AgentSealTiming.checked < AgentSealTiming.duration)
        #expect(AgentSealTiming.stillDuration < AgentSealTiming.duration)
    }

    @Test func itStartsWithAWideFrameAroundAWholePet() {
        let pose = AgentSealTiming.pose(at: 0)
        #expect(pose.frameScale == AgentSealTiming.frameStart)
        #expect(pose.roundness == 0)
        #expect(pose.petOpacity == 1)
        #expect(pose.petScale == 1)
        #expect(pose.mint == 0)
        #expect(pose.check == 0)
        #expect(pose.swell == 1)
    }

    @Test func theFrameClosesOnThePetBeforeItRounds() {
        let pose = AgentSealTiming.pose(at: AgentSealTiming.framed)
        #expect(pose.frameScale == 1)
        #expect(pose.roundness == 0)
        #expect(pose.petOpacity == 1)
    }

    @Test func thePetIsGoneOnceTheFrameIsRound() {
        let pose = AgentSealTiming.pose(at: AgentSealTiming.rounded)
        #expect(pose.roundness == 1)
        #expect(pose.petOpacity == 0)
        #expect(abs(pose.petScale - (1 - AgentSealTiming.petShrink)) < 1e-9)
        #expect(pose.check == 0)
    }

    @Test func itEndsAsAMintCircleWithACheck() {
        for time in [AgentSealTiming.checked, AgentSealTiming.duration] {
            let pose = AgentSealTiming.pose(at: time)
            #expect(pose.mint == 1)
            #expect(pose.check == 1)
            #expect(abs(pose.swell - 1) < 1e-9)
        }
    }

    @Test func theCircleSwellsWhileTheCheckLands() {
        let middle = (AgentSealTiming.rounded + AgentSealTiming.checked) / 2
        #expect(abs(AgentSealTiming.pose(at: middle).swell - (1 + AgentSealTiming.pop)) < 1e-9)
    }

    @Test func timeOutsideTheSealIsClamped() {
        #expect(AgentSealTiming.pose(at: -1) == AgentSealTiming.pose(at: 0))
        #expect(AgentSealTiming.pose(at: 10) == AgentSealTiming.finalPose)
    }
}
