import Foundation
import Testing
@testable import SymbiodockCore

struct CodexRolloutParserTests {
    private func data(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }

    private let rootMeta = """
        {"timestamp":"2026-11-14T13:36:47.100Z","ordinal":0,"type":"session_meta","payload":{"session_id":"t-root","id":"t-root","timestamp":"2026-11-14T13:36:47.000Z","cwd":"/Users/me/Projects/Demo","originator":"Codex Desktop","source":"vscode"}}
        """
    private let childMeta = """
        {"timestamp":"2026-11-14T13:40:00.000Z","type":"session_meta","payload":{"session_id":"t-root","id":"t-child","parent_thread_id":"t-root","cwd":"/Users/me","originator":"Codex Desktop","source":{"subagent":{"thread_spawn":{"parent_thread_id":"t-root"}}}}}
        """

    private func event(_ type: String, at time: String, extra: String = "") -> String {
        "{\"timestamp\":\"\(time)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"\(extra)}}"
    }

    @Test func readsARootThread() throws {
        let meta = try #require(CodexRolloutParser.meta(fromHead: data([rootMeta, "{\"cut"])))
        #expect(meta.id == "t-root")
        #expect(meta.cwd == "/Users/me/Projects/Demo")
        #expect(meta.originator == "Codex Desktop")
        #expect(!meta.isSubagent)
    }

    @Test func recognisesASubagentThread() throws {
        let meta = try #require(CodexRolloutParser.meta(fromHead: data([childMeta])))
        #expect(meta.id == "t-child")
        #expect(meta.isSubagent)
    }

    @Test func rejectsAHeadThatIsNotSessionMeta() {
        #expect(CodexRolloutParser.meta(fromHead: Data()) == nil)
        #expect(CodexRolloutParser.meta(fromHead: data(["not json"])) == nil)
        #expect(CodexRolloutParser.meta(fromHead: data([event("task_started", at: "2026-11-14T13:00:00Z")])) == nil)
        #expect(
            CodexRolloutParser.meta(fromHead: data(["{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/a\"}}"]))
                == nil)
    }

    @Test func anOpenTurnIsWorking() throws {
        let state = try #require(
            CodexRolloutParser.turnState(
                inTail: data([
                    event("task_started", at: "2026-11-14T18:00:00.000Z"),
                    event("task_complete", at: "2026-11-14T18:01:00.000Z"),
                    event("task_started", at: "2026-11-14T18:05:00.250Z"),
                    event("token_count", at: "2026-11-14T18:06:00.000Z"),
                ])))
        #expect(state.isWorking)
        #expect(state.since == Date(timeIntervalSince1970: 1_794_679_500.25))
    }

    @Test func aCompletedOrAbortedTurnIsIdle() throws {
        let done = try #require(
            CodexRolloutParser.turnState(
                inTail: data([
                    event("task_started", at: "2026-11-14T18:00:00.000Z"),
                    event("task_complete", at: "2026-11-14T18:01:00.000Z", extra: ",\"last_agent_message\":\"task_started again\""),
                ])))
        #expect(!done.isWorking)
        #expect(done.since == Date(timeIntervalSince1970: 1_794_679_260))

        let aborted = try #require(
            CodexRolloutParser.turnState(
                inTail: data([
                    event("task_started", at: "2026-11-14T18:00:00Z"),
                    event("turn_aborted", at: "2026-11-14T18:00:30Z"),
                ])))
        #expect(!aborted.isWorking)
    }

    @Test func aTailWithoutATurnHasNoState() {
        #expect(CodexRolloutParser.turnState(inTail: Data()) == nil)
        #expect(
            CodexRolloutParser.turnState(inTail: data([event("token_count", at: "2026-11-14T18:00:00Z")]))
                == nil)
        // A turn line without a readable time is not trusted.
        #expect(CodexRolloutParser.turnState(inTail: data([event("task_started", at: "soon")])) == nil)
    }

    @Test func hostileTimestampsAreNotTrusted() {
        for stamp in ["", "99999999999-01-01T00:00:00Z", "2026-13-45T99:99:99Z", "1e999", "2026-11-14T18:00:00+99:99"] {
            let tail = data(["{\"timestamp\":\"\(stamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}"])
            _ = CodexRolloutParser.turnState(inTail: tail)
        }
        let number = data(["{\"timestamp\":1e999,\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}"])
        #expect(CodexRolloutParser.turnState(inTail: number) == nil)
    }

    @Test func cutLinesAndOtherLineTypesAreSkipped() throws {
        let state = try #require(
            CodexRolloutParser.turnState(
                inTail: data([
                    "task_started\",\"cut\":true}}",
                    "{\"timestamp\":\"2026-11-14T18:00:00Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"task_started\"}}",
                    event("task_complete", at: "2026-11-14T18:01:00Z"),
                ])))
        #expect(!state.isWorking)
    }

    @Test func listingRule() {
        let now = Date(timeIntervalSince1970: 100_000)
        let working = CodexTurnState(isWorking: true, since: now)
        let idle = CodexTurnState(isWorking: false, since: now)
        #expect(CodexRolloutParser.isListed(idle, modified: now.addingTimeInterval(-29 * 60), now: now))
        #expect(!CodexRolloutParser.isListed(idle, modified: now.addingTimeInterval(-31 * 60), now: now))
        #expect(CodexRolloutParser.isListed(working, modified: now.addingTimeInterval(-119 * 60), now: now))
        #expect(!CodexRolloutParser.isListed(working, modified: now.addingTimeInterval(-121 * 60), now: now))
    }

    @Test func buildsASession() throws {
        let meta = try #require(CodexRolloutParser.meta(fromHead: data([rootMeta])))
        let since = Date(timeIntervalSince1970: 50)
        let working = CodexRolloutParser.session(
            meta: meta, state: CodexTurnState(isWorking: true, since: since),
            title: "Tune the monitor", pid: 99)
        #expect(working.id == "codex:t-root")
        #expect(working.tool == .codex)
        #expect(working.title == "Tune the monitor")
        #expect(working.projectPath == "/Users/me/Projects/Demo")
        #expect(working.activity == .working)
        #expect(working.since == since)
        #expect(working.pid == 99)

        let untitled = CodexRolloutParser.session(
            meta: meta, state: CodexTurnState(isWorking: false, since: since), title: nil, pid: nil)
        #expect(untitled.title == "Demo")
        #expect(untitled.activity == .idle)

        let bare = CodexRolloutParser.session(
            meta: CodexThreadMeta(id: "x", cwd: nil, isSubagent: false, originator: nil),
            state: CodexTurnState(isWorking: false, since: since), title: "  ", pid: nil)
        #expect(bare.title == "Codex")
    }

    @Test func indexKeepsTheLastTitleOfAThread() {
        let titles = CodexSessionIndex.titles(
            from: data([
                "cut\":\"line\"}",
                "{\"id\":\"t1\",\"thread_name\":\"Old name\",\"updated_at\":\"2026-11-14T11:00:00Z\"}",
                "{\"id\":\"t2\",\"thread_name\":\"Other\",\"updated_at\":\"2026-11-14T11:00:00Z\"}",
                "{\"id\":\"t1\",\"thread_name\":\"New name\",\"updated_at\":\"2026-11-14T12:00:00Z\"}",
                "{\"id\":\"t3\",\"thread_name\":\"\"}",
                "{\"thread_name\":\"No id\"}",
            ]))
        #expect(titles == ["t1": "New name", "t2": "Other"])
    }

    private let namedChildMeta = """
        {"timestamp":"2026-11-14T13:40:00.000Z","type":"session_meta","payload":{"session_id":"t-root","id":"t-named","timestamp":"2026-11-14T13:40:00.000Z","parent_thread_id":"t-root","cwd":"/Users/me","originator":"Codex Desktop","source":{"subagent":{"thread_spawn":{"parent_thread_id":"t-root","depth":1,"agent_path":"/root/notch_market_research","agent_nickname":"Carson","agent_role":"research-analyst"}}}}}
        """

    @Test func aSubagentKnowsItsParentNameAndStart() throws {
        let meta = try #require(CodexRolloutParser.meta(fromHead: data([namedChildMeta])))
        #expect(meta.parentID == "t-root")
        #expect(meta.subagentTitle == "notch market research")
        #expect(meta.started == Date(timeIntervalSince1970: 1_794_663_600))
        let unnamed = try #require(CodexRolloutParser.meta(fromHead: data([childMeta])))
        #expect(unnamed.parentID == "t-root")
        #expect(unnamed.subagentTitle == nil)
        let root = try #require(CodexRolloutParser.meta(fromHead: data([rootMeta])))
        #expect(root.parentID == nil)
    }

    @Test func aSubagentWithoutAPathIsNamedByItsNickname() throws {
        let line = namedChildMeta.replacingOccurrences(of: "\"agent_path\":\"/root/notch_market_research\",", with: "")
        let meta = try #require(CodexRolloutParser.meta(fromHead: data([line])))
        #expect(meta.subagentTitle == "Carson")
    }

    @Test func anAbortedTurnSaysSo() throws {
        let state = try #require(
            CodexRolloutParser.turnState(
                inTail: data([
                    event("task_started", at: "2026-11-14T18:00:00.000Z"),
                    event("turn_aborted", at: "2026-11-14T18:01:00.000Z"),
                ])))
        #expect(!state.isWorking)
        #expect(state.wasAborted)
    }

    @Test func aSubagentShowsWhileItWorksAndAfterItCompletes() throws {
        let meta = try #require(CodexRolloutParser.meta(fromHead: data([namedChildMeta])))
        let started = Date(timeIntervalSince1970: 1_794_663_600)
        let now = started.addingTimeInterval(600)
        let working = CodexRolloutParser.subagent(
            meta: meta, state: CodexTurnState(isWorking: true, since: started.addingTimeInterval(5)),
            modified: now.addingTimeInterval(-30), now: now)
        #expect(working == AgentSubagent(id: "t-named", title: "notch market research", isFinished: false, since: started))
        let quiet = CodexRolloutParser.subagent(
            meta: meta, state: CodexTurnState(isWorking: true, since: started),
            modified: now.addingTimeInterval(-601), now: now)
        #expect(quiet == nil)
        let doneAt = now.addingTimeInterval(-60)
        let done = CodexRolloutParser.subagent(
            meta: meta, state: CodexTurnState(isWorking: false, since: doneAt),
            modified: doneAt, now: now)
        #expect(done == AgentSubagent(id: "t-named", title: "notch market research", isFinished: true, since: doneAt))
        let aborted = CodexRolloutParser.subagent(
            meta: meta, state: CodexTurnState(isWorking: false, since: doneAt, wasAborted: true),
            modified: doneAt, now: now)
        #expect(aborted == nil)
        let root = try #require(CodexRolloutParser.meta(fromHead: data([rootMeta])))
        #expect(CodexRolloutParser.subagent(
            meta: root, state: CodexTurnState(isWorking: true, since: started), modified: now, now: now) == nil)
    }

    @Test func aFinishedSubagentIsListedAsLongAsAWorkingThread() throws {
        let meta = try #require(CodexRolloutParser.meta(fromHead: data([namedChildMeta])))
        let now = Date(timeIntervalSince1970: 1_794_670_000)
        func finished(agoSeconds: TimeInterval) -> AgentSubagent? {
            let modified = now.addingTimeInterval(-agoSeconds)
            return CodexRolloutParser.subagent(
                meta: meta, state: CodexTurnState(isWorking: false, since: modified),
                modified: modified, now: now)
        }
        #expect(finished(agoSeconds: 31 * 60) != nil)
        #expect(finished(agoSeconds: 2 * 3600) != nil)
        #expect(finished(agoSeconds: 2 * 3600 + 1) == nil)
    }

    private func restored(
        started: String?, stateAt: String, working: Bool = false, aborted: Bool = false
    ) -> Bool {
        let meta = CodexThreadMeta(
            id: "t", cwd: nil, isSubagent: false, originator: nil,
            started: started.flatMap(CodexRolloutParser.timestamp))
        let state = CodexTurnState(
            isWorking: working, since: CodexRolloutParser.timestamp(stateAt)!, wasAborted: aborted)
        return CodexRolloutParser.isRestoredCopy(meta: meta, state: state)
    }

    @Test func aTurnFinishedMomentsAfterTheStartIsARestoredCopy() {
        #expect(restored(started: "2026-11-16T14:16:46.184Z", stateAt: "2026-11-16T14:16:46.219Z"))
    }

    @Test func anAbortedTurnMomentsAfterTheStartIsARestoredCopy() {
        #expect(restored(started: "2026-11-16T14:16:46.000Z", stateAt: "2026-11-16T14:16:46.500Z", aborted: true))
    }

    @Test func aTurnFinishedMinutesAfterTheStartIsARealThread() {
        #expect(!restored(started: "2026-11-16T14:18:23.319Z", stateAt: "2026-11-16T14:25:19.613Z"))
    }

    @Test func aTurnFinishedExactlyAtTheWindowIsARealThread() {
        #expect(!restored(started: "2026-11-16T14:00:00.000Z", stateAt: "2026-11-16T14:00:02.000Z"))
    }

    @Test func aWorkingStateIsNeverARestoredCopy() {
        #expect(!restored(started: "2026-11-16T14:00:00.000Z", stateAt: "2026-11-16T14:00:00.500Z", working: true))
    }

    @Test func aThreadWithUnknownStartIsNeverARestoredCopy() {
        #expect(!restored(started: nil, stateAt: "2026-11-16T14:00:00.500Z"))
    }

    @Test func aSubagentHangsUnderTheListedThreadItDescendsFrom() {
        let parents = ["c": "b", "b": "a", "x": "y", "y": "x"]
        #expect(CodexRolloutParser.rootID(of: "c", parents: parents, listed: ["a"]) == "a")
        #expect(CodexRolloutParser.rootID(of: "b", parents: parents, listed: ["a"]) == "a")
        #expect(CodexRolloutParser.rootID(of: "c", parents: parents, listed: []) == nil)
        #expect(CodexRolloutParser.rootID(of: "x", parents: parents, listed: ["a"]) == nil)
    }
}
