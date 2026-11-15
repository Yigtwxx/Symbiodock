import Foundation
import Testing
@testable import SymbiodockCore

struct AgentBranchesTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func sub(_ id: String, finished: Bool = false, at offset: TimeInterval) -> AgentSubagent {
        AgentSubagent(id: id, title: id, isFinished: finished, since: base.addingTimeInterval(offset))
    }

    private func ids(_ lines: [AgentBranch]) -> [String] {
        lines.map { line in
            switch line {
            case .subagent(let subagent): subagent.id
            case .more(let count): "+\(count)"
            }
        }
    }

    @Test func workingComeFirstOldestFirst() {
        let lines = AgentBranches.lines(
            for: [sub("f", finished: true, at: 20), sub("w-new", at: 15), sub("w-old", at: 5)],
            state: .working, turnStart: base)
        #expect(ids(lines) == ["w-old", "w-new", "f"])
    }

    @Test func finishedComeNewestFirst() {
        let lines = AgentBranches.lines(
            for: [sub("f-old", finished: true, at: 20), sub("f-new", finished: true, at: 30)],
            state: .needsInput(prompt: nil), turnStart: base)
        #expect(ids(lines) == ["f-new", "f-old"])
    }

    @Test func threeLinesAtMostTheRestCounted() {
        let three = (1...3).map { sub("w\($0)", at: TimeInterval($0)) }
        #expect(ids(AgentBranches.lines(for: three, state: .working, turnStart: base)) == ["w1", "w2", "w3"])
        let five = (1...5).map { sub("w\($0)", at: TimeInterval($0)) }
        #expect(ids(AgentBranches.lines(for: five, state: .working, turnStart: base)) == ["w1", "w2", "+3"])
    }

    @Test func finishedBeforeTheTurnStartAreLeftOut() {
        let lines = AgentBranches.lines(
            for: [sub("before", finished: true, at: 5), sub("at", finished: true, at: 10)],
            state: .working, turnStart: base.addingTimeInterval(10))
        #expect(ids(lines) == ["at"])
    }

    @Test func finishedShowOnlyWhileTheParentIsActive() {
        let subagents = [sub("w", at: 1), sub("f", finished: true, at: 2)]
        for state in [AgentRowState.idle, .finished, .running] {
            #expect(ids(AgentBranches.lines(for: subagents, state: state, turnStart: base)) == ["w"])
        }
        #expect(ids(AgentBranches.lines(for: subagents, state: .working, turnStart: nil)) == ["w"])
    }

    @Test func aBranchIdTellsSubagentsAndTheCountApart() {
        #expect(AgentBranch.subagent(sub("x", at: 0)).id == "s:x")
        #expect(AgentBranch.more(2).id == "more")
    }
}
