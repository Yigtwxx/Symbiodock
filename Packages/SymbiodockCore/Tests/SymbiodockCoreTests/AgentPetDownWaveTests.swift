import Foundation
import Testing
@testable import SymbiodockCore

struct AgentPetDownWaveTests {
    @Test func theCrestEntersAboveAndLeavesBelow() throws {
        #expect(AgentPetMotion.downCrestRange.lowerBound < 0)
        #expect(AgentPetMotion.downCrestRange.upperBound > 1)
        #expect(AgentPetMotion.downCrest(at: 0) == AgentPetMotion.downCrestRange.lowerBound)
        let late = try #require(AgentPetMotion.downCrest(at: AgentPetMotion.waveTravel - 0.0001))
        #expect(abs(late - AgentPetMotion.downCrestRange.upperBound) < 0.001)
    }

    @Test func theCrestOnlyGoesDown() throws {
        var last = -Double.infinity
        for time in stride(from: 0.0, to: AgentPetMotion.waveTravel, by: 0.05) {
            let crest = try #require(AgentPetMotion.downCrest(at: time))
            #expect(crest > last)
            last = crest
        }
    }

    @Test func thePetRestsOnceTheCrestHasPassed() {
        #expect(AgentPetMotion.downCrest(at: AgentPetMotion.waveTravel) == nil)
        #expect(AgentPetMotion.downCrest(at: AgentPetMotion.wavePeriod - 0.01) == nil)
        for y in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(AgentPetMotion.waveDown(y: y, at: AgentPetMotion.waveTravel + 0.1) == 0)
        }
    }

    @Test func itRepeatsEveryPeriod() throws {
        let first = try #require(AgentPetMotion.downCrest(at: 0.4))
        let later = try #require(AgentPetMotion.downCrest(at: 0.4 + 3 * AgentPetMotion.wavePeriod))
        let earlier = try #require(AgentPetMotion.downCrest(at: 0.4 - AgentPetMotion.wavePeriod))
        #expect(abs(first - later) < 1e-9)
        #expect(abs(first - earlier) < 1e-9)
    }

    @Test func thePartAtTheCrestIsFullyForward() {
        let half = AgentPetMotion.waveTravel / 2
        #expect(abs(AgentPetMotion.waveDown(y: 0.5, at: half) - 1) < 1e-9)
        #expect(AgentPetMotion.waveDown(y: 0, at: half) == 0)
        #expect(AgentPetMotion.waveDown(y: 1, at: half) == 0)
    }

    @Test func everyPartRestsWhenACrestBegins() {
        for y in stride(from: 0.0, through: 1.0, by: 0.05) {
            #expect(AgentPetMotion.waveDown(y: y, at: 0) == 0)
        }
    }
}
