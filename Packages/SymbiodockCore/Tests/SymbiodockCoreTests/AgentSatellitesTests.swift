import Foundation
import Testing
@testable import SymbiodockCore

struct AgentSatellitesTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func sub(_ id: String, finished: Bool = false, at offset: TimeInterval) -> AgentSubagent {
        AgentSubagent(id: id, title: id, isFinished: finished, since: base.addingTimeInterval(offset))
    }

    @Test func onlyWorkingSubagentsOrbitOldestFirst() {
        let orbiters = AgentSatellites.orbiters(
            for: [sub("new", at: 20), sub("done", finished: true, at: 1), sub("old", at: 5)],
            state: .working)
        #expect(orbiters.map(\.id) == ["old", "new"])
    }

    @Test func nothingOrbitsUnlessTheSessionWorks() {
        let subagents = [sub("a", at: 1)]
        #expect(AgentSatellites.orbiters(for: subagents, state: .needsInput(prompt: nil)).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .compacting).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .finished).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .running).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .idle).isEmpty)
    }

    @Test func atMostFiveOrbit() {
        let seven = (1...7).map { sub("s\($0)", at: TimeInterval($0)) }
        let orbiters = AgentSatellites.orbiters(for: seven, state: .working)
        #expect(orbiters.map(\.id) == ["s1", "s2", "s3", "s4", "s5"])
    }

    @Test func aSubagentKeepsItsPeriodAndPhase() {
        let alone = AgentSatellites.orbiters(for: [sub("x", at: 1)], state: .working)[0]
        let among = AgentSatellites.orbiters(for: [sub("w", at: 0), sub("x", at: 9)], state: .working)[1]
        #expect(alone.period == among.period)
        #expect(alone.phase == among.phase)
        #expect(alone.period == AgentSatellites.period(of: "x"))
        #expect(alone.phase == AgentSatellites.phase(of: "x"))
    }

    @Test func periodsAndPhasesStayInRangeAndDiffer() {
        let ids = (0..<200).map { "agent-\($0)" }
        for id in ids {
            #expect(AgentSatellites.periodRange.contains(AgentSatellites.period(of: id)))
            #expect((0..<1).contains(AgentSatellites.phase(of: id)))
        }
        #expect(Set(ids.map { AgentSatellites.period(of: $0) }).count > 100)
        #expect(Set(ids.map { AgentSatellites.phase(of: $0) }).count > 100)
    }

    @Test func satellitesShownTogetherHaveDifferentTones() {
        let four = (1...4).map { sub("s\($0)", at: TimeInterval($0)) }
        let tones = AgentSatellites.orbiters(for: four, state: .working).map(\.tone)
        #expect(Set(tones) == [0, 1, 2, 3])
        // A fifth has to share one.
        let five = (1...5).map { sub("s\($0)", at: TimeInterval($0)) }
        let all = AgentSatellites.orbiters(for: five, state: .working).map(\.tone)
        #expect(all.allSatisfy { (0..<AgentSatellites.toneCount).contains($0) })
        // Alone, a satellite has the tone of its own id.
        let alone = AgentSatellites.orbiters(for: [sub("s3", at: 1)], state: .working)[0]
        #expect(alone.tone == AgentBranches.tone(of: "s3", count: AgentSatellites.toneCount))
    }

    @Test func aSatelliteTurnsOnceInItsPeriod() {
        let satellite = AgentSatellite(id: "x", period: 3, phase: 0.25, tone: 0)
        #expect(abs(AgentSatellites.turn(of: satellite, at: 0) - 0.25) < 1e-9)
        #expect(abs(AgentSatellites.turn(of: satellite, at: 1.5) - 0.75) < 1e-9)
        #expect(abs(AgentSatellites.turn(of: satellite, at: 3) - 0.25) < 1e-9)
        #expect(abs(AgentSatellites.turn(of: satellite, at: -0.75) - 0) < 1e-9)
    }

    @Test func stillSatellitesStandEvenlyApart() {
        #expect(AgentSatellites.stillTurn(index: 0, count: 4) == 0)
        #expect(AgentSatellites.stillTurn(index: 1, count: 4) == 0.25)
        #expect(AgentSatellites.stillTurn(index: 3, count: 4) == 0.75)
        #expect(AgentSatellites.stillTurn(index: 0, count: 0) == 0)
    }

    @Test func aRowCarriesItsOrbiters() {
        var session = AgentSession(
            id: "a", tool: .claudeCode, title: "t", projectPath: nil, activity: .working, since: base, pid: nil)
        session.subagents = [sub("one", at: 1), sub("gone", finished: true, at: 2)]
        var board = AgentSessionBoard()
        board.update([session])
        #expect(board.rows[0].orbiters.map(\.id) == ["one"])
    }
}
