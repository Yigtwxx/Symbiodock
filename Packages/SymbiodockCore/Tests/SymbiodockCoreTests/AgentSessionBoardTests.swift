import Foundation
import Testing
@testable import SymbiodockCore

struct AgentSessionBoardTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String, _ activity: AgentActivity, since offset: TimeInterval = 0
    ) -> AgentSession {
        AgentSession(
            id: id, tool: .claudeCode, title: id, projectPath: "/work/\(id)",
            activity: activity, since: base.addingTimeInterval(offset), pid: nil)
    }

    @Test func startsEmptyAndQuiet() {
        let board = AgentSessionBoard()
        #expect(board.rows.isEmpty)
        #expect(board.attention == .none)
        #expect(board.lead == nil)
        #expect(!board.hasFace)
    }

    @Test func sortsByUrgencyThenByMostRecent() {
        var board = AgentSessionBoard()
        board.update([
            session("idle", .idle),
            session("running", .running),
            session("old-work", .working, since: 10),
            session("new-work", .working, since: 20),
            session("ask", .needsInput(prompt: "Go on?")),
        ])
        #expect(board.rows.map(\.id) == ["ask", "new-work", "old-work", "running", "idle"])
        #expect(board.lead?.id == "ask")
        #expect(board.attention == .needsInput)
        #expect(board.needsInputCount == 1)
        #expect(board.workingCount == 2)
    }

    @Test func aSessionSeenWorkingThenIdleIsFinished() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        board.update([session("a", .idle, since: 5)])
        #expect(board.rows.map(\.state) == [.finished])
        #expect(board.attention == .finished)
        #expect(board.hasFace)
    }

    @Test func aSessionAlreadyIdleAtFirstSightIsNotFinished() {
        var board = AgentSessionBoard()
        board.update([session("a", .idle)])
        #expect(board.rows.map(\.state) == [.idle])
        #expect(board.attention == .none)
        #expect(!board.hasFace)
    }

    @Test func answeringAQuestionAndStoppingAlsoCountsAsFinished() {
        var board = AgentSessionBoard()
        board.update([session("a", .needsInput(prompt: nil))])
        board.update([session("a", .idle)])
        #expect(board.rows.map(\.state) == [.finished])
    }

    @Test func markSeenClearsFinishedMarks() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        board.update([session("a", .idle)])
        board.markSeen()
        #expect(board.rows.map(\.state) == [.idle])
        #expect(board.attention == .none)
        // It stays cleared on the next identical update.
        board.update([session("a", .idle)])
        #expect(board.rows.map(\.state) == [.idle])
    }

    @Test func workingAgainDropsTheFinishedMark() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        board.update([session("a", .idle)])
        board.update([session("a", .working)])
        #expect(board.rows.map(\.state) == [.working])
        #expect(board.attention == .none)
    }

    @Test func aSessionThatDisappearsLeavesNoMark() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        board.update([session("a", .idle)])
        board.update([])
        board.update([session("a", .idle)])
        #expect(board.rows.map(\.state) == [.idle])
    }

    @Test func idleAndRunningSessionsGiveNoFace() {
        var board = AgentSessionBoard()
        board.update([session("a", .idle), session("b", .running)])
        #expect(board.lead == nil)
        #expect(!board.hasFace)
        #expect(board.rows.count == 2)
    }

    @Test func duplicateIDsKeepTheFirst() {
        var board = AgentSessionBoard()
        board.update([session("a", .working), session("a", .idle)])
        #expect(board.rows.map(\.state) == [.working])
    }

    @Test func equalInputsGiveEqualBoards() {
        var first = AgentSessionBoard()
        var second = AgentSessionBoard()
        first.update([session("a", .working), session("b", .idle)])
        second.update([session("b", .idle), session("a", .working)])
        #expect(first == second)
    }

    @Test func projectNameIsTheLastPathComponent() {
        #expect(session("a", .idle).projectName == "a")
        let bare = AgentSession(
            id: "x", tool: .codex, title: "x", projectPath: nil, activity: .idle,
            since: base, pid: nil)
        #expect(bare.projectName == nil)
    }
}
