import Foundation
import Testing
@testable import SymbiodockCore

struct ClaudeTranscriptPromptReaderTests {
    private func ask(id: String, _ question: String) -> String {
        """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\(id)","name":"AskUserQuestion","input":{"questions":[{"question":"\(question)","header":"H","multiSelect":false,"options":[]}]}}]}}
        """
    }

    private func result(for id: String) -> String {
        """
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\(id)","content":"ok"}]}}
        """
    }

    private let otherTool = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t9","name":"Bash","input":{"command":"ls"}}]}}
        """

    private func read(_ lines: [String]) -> String? {
        ClaudeTranscriptPromptReader.pendingQuestion(
            inTail: Data(lines.joined(separator: "\n").utf8))
    }

    @Test func findsAnOpenQuestion() {
        #expect(read([otherTool, ask(id: "t1", "Which tools first?")]) == "Which tools first?")
    }

    @Test func anAnsweredQuestionIsNotPending() {
        #expect(read([ask(id: "t1", "Which tools first?"), result(for: "t1")]) == nil)
    }

    @Test func aResultForAnotherCallDoesNotAnswerIt() {
        #expect(read([ask(id: "t1", "Which tools first?"), result(for: "t0")]) == "Which tools first?")
    }

    @Test func aLaterToolCallMeansTheTalkMovedOn() {
        #expect(read([ask(id: "t1", "Which tools first?"), otherTool]) == nil)
    }

    @Test func theLatestQuestionWins() {
        #expect(
            read([ask(id: "t1", "First?"), result(for: "t1"), ask(id: "t2", "Second?")]) == "Second?")
    }

    @Test func aCutFirstLineAndGarbageAreSkipped() {
        #expect(
            read(["tool_use\",\"id\":\"broken", "not json at all", ask(id: "t1", "Still here?")])
                == "Still here?")
    }

    @Test func nothingToFind() {
        #expect(read([]) == nil)
        #expect(read([otherTool]) == nil)
        #expect(ClaudeTranscriptPromptReader.pendingQuestion(inTail: Data()) == nil)
    }

    @Test func aQuestionWithoutTextIsNotAPrompt() {
        let empty = """
            {"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"AskUserQuestion","input":{"questions":[]}}]}}
            """
        #expect(read([empty]) == nil)
    }

    @Test func lineBreaksBecomeSpacesAndLongTextIsCut() {
        #expect(read([ask(id: "t1", "One\\nTwo")]) == "One Two")
        let long = String(repeating: "a", count: 400)
        #expect(read([ask(id: "t1", long)])?.count == 300)
    }
}
