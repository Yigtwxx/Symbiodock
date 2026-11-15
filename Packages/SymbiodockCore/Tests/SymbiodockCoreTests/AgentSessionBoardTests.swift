import Foundation
import Testing
@testable import SymbiodockCore

struct AgentSessionBoardTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func session(
        _ id: String, _ activity: AgentActivity, since offset: TimeInterval = 0,
        subagents: [AgentSubagent] = []
    ) -> AgentSession {
        AgentSession(
            id: id, tool: .claudeCode, title: id, projectPath: "/work/\(id)",
            activity: activity, since: base.addingTimeInterval(offset), pid: nil,
            subagents: subagents)
    }

    private func sub(_ id: String, finished: Bool = false, at offset: TimeInterval) -> AgentSubagent {
        AgentSubagent(id: id, title: id, isFinished: finished, since: base.addingTimeInterval(offset))
    }

    private func branchIDs(_ board: AgentSessionBoard) -> [String] {
        (board.rows.first?.branches ?? []).map { line in
            switch line {
            case .subagent(let subagent): subagent.id
            case .more(let count): "+\(count)"
            }
        }
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

    @Test func needsInputWinsOverFinishedAsTheAttentionRow() {
        var board = AgentSessionBoard()
        board.update([session("done", .working), session("ask", .working, since: 5)])
        board.update([session("done", .idle), session("ask", .needsInput(prompt: nil), since: 5)])
        #expect(board.rows.map(\.state) == [.needsInput(prompt: nil), .finished])
        #expect(board.attentionRow?.id == "ask")
    }

    @Test func aFinishedRowIsFoundBehindAWorkingOne() {
        var board = AgentSessionBoard()
        board.update([session("done", .working), session("busy", .working, since: 5)])
        board.update([session("done", .idle), session("busy", .working, since: 5)])
        #expect(board.lead?.id == "busy")
        #expect(board.attention == .finished)
        #expect(board.attentionRow?.id == "done")
        #expect(board.attentionRow?.state == .finished)
    }

    @Test func noAttentionRowWhenNothingWantsAttention() {
        var board = AgentSessionBoard()
        #expect(board.attentionRow == nil)
        board.update([session("busy", .working), session("open", .running), session("idle", .idle)])
        #expect(board.attention == .none)
        #expect(board.attentionRow == nil)
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

    @Test func theSpokespersonIsTheLeadOrElseTheFirstRow() {
        var board = AgentSessionBoard()
        #expect(board.spokesperson == nil)
        board.update([session("idle", .idle), session("running", .running)])
        #expect(board.lead == nil)
        #expect(board.spokesperson?.id == board.rows.first?.id)
        board.update([session("idle", .idle), session("work", .working)])
        #expect(board.spokesperson?.id == "work")
        #expect(board.spokesperson?.id == board.lead?.id)
    }

    @Test func theTurnStartSurvivesAQuestion() {
        let done = sub("done", finished: true, at: 5)
        var board = AgentSessionBoard()
        board.update([session("a", .working, since: 0, subagents: [done])])
        #expect(branchIDs(board) == ["done"])
        board.update([session("a", .needsInput(prompt: nil), since: 10, subagents: [done])])
        #expect(branchIDs(board) == ["done"])
        board.update([session("a", .working, since: 20, subagents: [done])])
        #expect(branchIDs(board) == ["done"])
    }

    @Test func subagentsFinishedBeforeTheTurnAreLeftOut() {
        var board = AgentSessionBoard()
        board.update([
            session("a", .working, since: 10, subagents: [
                sub("early", finished: true, at: -5), sub("late", finished: true, at: 12),
            ]),
        ])
        #expect(branchIDs(board) == ["late"])
    }

    @Test func aBackgroundSubagentThatEndedWhileIdleShowsDoneInTheTurnItStarts() {
        var board = AgentSessionBoard()
        board.update([session("a", .idle, since: 0, subagents: [sub("bg", at: 1)])])
        board.update([session("a", .working, since: 32, subagents: [sub("bg", finished: true, at: 30)])])
        #expect(branchIDs(board) == ["bg"])
    }

    @Test func finishedSubagentsGoWhenTheParentIdles() {
        let done = sub("done", finished: true, at: 5)
        var board = AgentSessionBoard()
        board.update([session("a", .working, since: 0, subagents: [done])])
        board.update([session("a", .idle, since: 30, subagents: [done])])
        #expect(board.rows.map(\.state) == [.finished])
        #expect(branchIDs(board).isEmpty)
    }

    @Test func aNewTurnStartsAfresh() {
        let done = sub("done", finished: true, at: 5)
        var board = AgentSessionBoard()
        board.update([session("a", .working, since: 0, subagents: [done])])
        board.update([session("a", .idle, since: 30, subagents: [done])])
        board.update([session("a", .working, since: 100, subagents: [done])])
        #expect(branchIDs(board).isEmpty)
    }

    @Test func aBackgroundSubagentShowsUnderAnIdleParent() {
        var board = AgentSessionBoard()
        board.update([session("a", .idle, since: 0, subagents: [sub("w", at: 3)])])
        #expect(branchIDs(board) == ["w"])
    }

    @Test func markSeenKeepsTheBranches() {
        var board = AgentSessionBoard()
        board.update([session("a", .working, subagents: [sub("w", at: 1)])])
        board.update([session("a", .idle, since: 5, subagents: [sub("w", at: 1)])])
        board.markSeen()
        #expect(branchIDs(board) == ["w"])
    }
}
