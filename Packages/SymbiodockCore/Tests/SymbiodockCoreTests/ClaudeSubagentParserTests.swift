import Foundation
import Testing
@testable import SymbiodockCore

struct ClaudeSubagentParserTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private let running = Data(#"{"agentType":"general-purpose","isBuiltIn":true,"description":"Review the parser","toolUseId":"toolu_01ABC","spawnDepth":1,"requestShape":"background","requestNonInteractive":true,"model":"haiku"}"#.utf8)
    private let finished = Data(#"{"agentType":"Explore","description":"Map the views","toolUseId":"toolu_02DEF","spawnDepth":1,"requestShape":"foreground","finished":true}"#.utf8)

    @Test func readsARunningBackgroundSubagent() throws {
        let meta = try #require(ClaudeSubagentParser.meta(from: running))
        #expect(meta.title == "Review the parser")
        #expect(!meta.isFinished)
        #expect(meta.toolUseID == "toolu_01ABC")
        #expect(meta.isBackground)
    }

    @Test func readsAFinishedForegroundSubagent() throws {
        let meta = try #require(ClaudeSubagentParser.meta(from: finished))
        #expect(meta.title == "Map the views")
        #expect(meta.isFinished)
        #expect(!meta.isBackground)
    }

    @Test func theTitleFallsBackToTheTypeThenToSubagent() throws {
        let typed = try #require(ClaudeSubagentParser.meta(from: Data(#"{"description":"  ","agentType":"Plan"}"#.utf8)))
        #expect(typed.title == "Plan")
        let bare = try #require(ClaudeSubagentParser.meta(from: Data("{}".utf8)))
        #expect(bare.title == "Subagent")
    }

    @Test func rejectsMalformedOrOversizedMeta() {
        #expect(ClaudeSubagentParser.meta(from: Data("nope".utf8)) == nil)
        #expect(ClaudeSubagentParser.meta(from: Data("[1]".utf8)) == nil)
        let long = String(repeating: "a", count: ClaudeSubagentParser.maximumMetaSize)
        #expect(ClaudeSubagentParser.meta(from: Data(#"{"description":"\#(long)"}"#.utf8)) == nil)
    }

    @Test func takesTheIdFromAMetaFileName() {
        #expect(ClaudeSubagentParser.agentID(metaFileName: "agent-a9d610fe0de7c020e.meta.json") == "a9d610fe0de7c020e")
        #expect(ClaudeSubagentParser.agentID(metaFileName: "agent-a9d610fe0de7c020e.jsonl") == nil)
        #expect(ClaudeSubagentParser.agentID(metaFileName: "agent-.meta.json") == nil)
        #expect(ClaudeSubagentParser.agentID(metaFileName: "agent-../x.meta.json") == nil)
        #expect(ClaudeSubagentParser.agentID(metaFileName: "other.meta.json") == nil)
    }

    @Test func theFolderLiesBesideTheTranscript() {
        #expect(
            ClaudeSubagentParser.folderRelativePath(cwd: "/Users/me/Projects/Demo", sessionID: "abc-1")
                == "projects/-Users-me-Projects-Demo/abc-1/subagents")
        #expect(ClaudeSubagentParser.folderRelativePath(cwd: "/Users/me", sessionID: "") == nil)
    }

    @Test func findsWhichSubagentsTheParentSawEnd() throws {
        let background = try #require(ClaudeSubagentParser.meta(from: running))
        let foreground = try #require(ClaudeSubagentParser.meta(from: Data(#"{"toolUseId":"toolu_02DEF","requestShape":"foreground"}"#.utf8)))
        let quiet = try #require(ClaudeSubagentParser.meta(from: Data(#"{"toolUseId":"toolu_04JKL","requestShape":"background"}"#.utf8)))
        let tail = Data([
            #"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>a1</task-id>\n<status>killed</status>\n</task-notification>"}"#,
            #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_02DEF","type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_04JKL","type":"tool_result","content":"Async agent launched"}]}}"#,
        ].joined(separator: "\n").utf8)
        let ended = ClaudeSubagentParser.endedIDs(
            [(id: "a1", meta: background), (id: "a2", meta: foreground), (id: "a3", meta: background),
             (id: "a4", meta: quiet)],
            inTail: tail)
        // a3: no notification names it. a4: a background subagent's tool result comes at its
        // launch, so it says nothing about its end.
        #expect(ended == ["a1", "a2"])
    }

    @Test func aFinishedSubagentShowsWhenItFinished() throws {
        let meta = try #require(ClaudeSubagentParser.meta(from: finished))
        let recent = ClaudeSubagentParser.subagent(
            id: "f", meta: meta, started: now.addingTimeInterval(-300), lastWrite: now.addingTimeInterval(-60),
            metaModified: now.addingTimeInterval(-60), hasEnded: true, now: now)
        #expect(recent == AgentSubagent(id: "f", title: "Map the views", isFinished: true, since: now.addingTimeInterval(-60)))
        let old = ClaudeSubagentParser.subagent(
            id: "f", meta: meta, started: now.addingTimeInterval(-9000), lastWrite: now.addingTimeInterval(-7300),
            metaModified: now.addingTimeInterval(-7300), hasEnded: false, now: now)
        #expect(old == nil)
    }

    @Test func aRunningSubagentShowsSinceItStartedUntilItEndsOrGoesQuiet() throws {
        let meta = try #require(ClaudeSubagentParser.meta(from: running))
        func subagent(lastWrite: TimeInterval, hasEnded: Bool) -> AgentSubagent? {
            ClaudeSubagentParser.subagent(
                id: "r", meta: meta, started: now.addingTimeInterval(-900), lastWrite: now.addingTimeInterval(lastWrite),
                metaModified: now.addingTimeInterval(-900), hasEnded: hasEnded, now: now)
        }
        #expect(subagent(lastWrite: -5, hasEnded: false)
            == AgentSubagent(id: "r", title: "Review the parser", isFinished: false, since: now.addingTimeInterval(-900)))
        #expect(subagent(lastWrite: -600, hasEnded: false) != nil)
        #expect(subagent(lastWrite: -601, hasEnded: false) == nil)
        #expect(subagent(lastWrite: -5, hasEnded: true) == nil)
    }
}
