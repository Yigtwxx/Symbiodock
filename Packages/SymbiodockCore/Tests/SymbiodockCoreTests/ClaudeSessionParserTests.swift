import Foundation
import Testing
@testable import SymbiodockCore

struct ClaudeSessionParserTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let busy = """
        {"pid":4242,"sessionId":"aaaa1111-bbbb-2222-cccc-333344445555","cwd":"/Users/me/Projects/Demo",
         "startedAt":1794660910455,"version":"2.1.325","kind":"interactive","name":"fix-login",
         "status":"busy","updatedAt":1794685284475,"statusUpdatedAt":1794685284475}
        """

    @Test func readsTheFieldsOfASessionFile() throws {
        let record = try #require(ClaudeSessionParser.record(from: data(busy)))
        #expect(record.pid == 4242)
        #expect(record.sessionID == "aaaa1111-bbbb-2222-cccc-333344445555")
        #expect(record.cwd == "/Users/me/Projects/Demo")
        #expect(record.name == "fix-login")
        #expect(record.status == "busy")
        #expect(record.waitingFor == nil)
        #expect(record.statusUpdatedAt == Date(timeIntervalSince1970: 1_794_685_284.475))
        #expect(!record.isSpare)
    }

    @Test func rejectsWhatIsNotASessionFile() {
        #expect(ClaudeSessionParser.record(from: data("")) == nil)
        #expect(ClaudeSessionParser.record(from: data("[1,2]")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"status\":\"busy\"}")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":\"4242\"}")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":0}")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":4242")) == nil)
    }

    @Test func rejectsPidsThatAreNotPids() {
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":true}")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":4294967297}")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":1e300}")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":-5}")) == nil)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":12.5}")) == nil)
    }

    @Test func ignoresATimeThatIsNotATime() throws {
        for value in ["1e300", "-1", "0", "true"] {
            let record = try #require(
                ClaudeSessionParser.record(from: data("{\"pid\":7,\"statusUpdatedAt\":\(value)}")))
            #expect(record.statusUpdatedAt == nil, "\(value)")
        }
    }

    @Test func rejectsAnOversizedFile() {
        let padding = String(repeating: " ", count: ClaudeSessionParser.maximumFileSize)
        #expect(ClaudeSessionParser.record(from: data("{\"pid\":4242}" + padding)) == nil)
    }

    @Test func ignoresFieldsOfTheWrongType() throws {
        let record = try #require(
            ClaudeSessionParser.record(
                from: data("{\"pid\":7,\"name\":12,\"status\":null,\"statusUpdatedAt\":\"x\",\"spare\":\"yes\"}")))
        #expect(record.name == nil)
        #expect(record.status == nil)
        #expect(record.statusUpdatedAt == nil)
        #expect(!record.isSpare)
    }

    private let fallback = Date(timeIntervalSince1970: 500)

    private func session(_ json: String, prompt: String? = nil) -> AgentSession? {
        ClaudeSessionParser.record(from: data(json)).flatMap {
            ClaudeSessionParser.session(from: $0, prompt: prompt, fallbackSince: fallback)
        }
    }

    @Test func aBusySessionIsWorking() throws {
        let session = try #require(session(busy))
        #expect(session.id == "claudeCode:4242")
        #expect(session.tool == .claudeCode)
        #expect(session.title == "fix-login")
        #expect(session.projectPath == "/Users/me/Projects/Demo")
        #expect(session.activity == .working)
        #expect(session.since == Date(timeIntervalSince1970: 1_794_685_284.475))
        #expect(session.pid == 4242)
    }

    @Test func statusesMapToActivities() {
        #expect(session("{\"pid\":1,\"status\":\"idle\"}")?.activity == .idle)
        #expect(session("{\"pid\":1,\"status\":\"waiting\"}")?.activity == .needsInput(prompt: nil))
        #expect(
            session("{\"pid\":1,\"status\":\"waiting\"}", prompt: "Which one?")?.activity
                == .needsInput(prompt: "Which one?"))
        #expect(session("{\"pid\":1,\"status\":\"sleeping\"}")?.activity == .running)
        #expect(session("{\"pid\":1}")?.activity == .running)
    }

    @Test func aPromptIsKeptOnlyWhileWaiting() {
        #expect(session("{\"pid\":1,\"status\":\"busy\"}", prompt: "Which one?")?.activity == .working)
    }

    @Test func theTitleFallsBackToTheFolderThenTheTool() {
        #expect(session("{\"pid\":1,\"cwd\":\"/Users/me/Projects/Demo\"}")?.title == "Demo")
        #expect(session("{\"pid\":1,\"name\":\"  \",\"cwd\":\"/Users/me/Projects/Demo\"}")?.title == "Demo")
        #expect(session("{\"pid\":1}")?.title == "Claude Code")
    }

    @Test func sinceFallsBackWhenTheFileDoesNotSay() {
        #expect(session("{\"pid\":1}")?.since == fallback)
    }

    @Test func aSpareProcessIsNotASession() {
        #expect(session("{\"pid\":1,\"status\":\"idle\",\"spare\":true}") == nil)
    }

    @Test func transcriptPathReplacesEverythingButLettersAndDigits() {
        #expect(
            ClaudeSessionParser.transcriptRelativePath(
                cwd: "/Users/me/Projects/Demo", sessionID: "aaaa1111-bbbb")
                == "projects/-Users-me-Projects-Demo/aaaa1111-bbbb.jsonl")
        #expect(
            ClaudeSessionParser.transcriptRelativePath(
                cwd: "/private/tmp/claude-501/-Users-me/my.app_v2", sessionID: "id1")
                == "projects/-private-tmp-claude-501--Users-me-my-app-v2/id1.jsonl")
    }

    @Test func transcriptPathRefusesASuspiciousSessionID() {
        #expect(ClaudeSessionParser.transcriptRelativePath(cwd: "/a", sessionID: "../../etc") == nil)
        #expect(ClaudeSessionParser.transcriptRelativePath(cwd: "/a", sessionID: "") == nil)
        #expect(ClaudeSessionParser.transcriptRelativePath(cwd: "", sessionID: "id1") == nil)
    }

    // MARK: liveness

    private func process(
        _ pid: Int32, path: String = "/usr/local/bin/claude", started: Date
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid, parentPID: 1, executablePath: path, startTime: started, terminal: nil)
    }

    private let written = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aProcessThatStartedBeforeTheFileIsLive() {
        let processes = [process(4242, started: written.addingTimeInterval(-3600))]
        #expect(ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: processes))
    }

    @Test func aMissingProcessIsNotLive() {
        let processes = [process(1, started: written.addingTimeInterval(-3600))]
        #expect(!ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: processes))
    }

    @Test func anotherUsersProcessIsNotLive() {
        let processes = [process(4242, path: "", started: written.addingTimeInterval(-3600))]
        #expect(!ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: processes))
    }

    @Test func aPidReusedAfterTheFileWasWrittenIsNotLive() {
        let processes = [process(4242, started: written.addingTimeInterval(60))]
        #expect(!ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: processes))
    }

    @Test func aProcessStartedJustBeforeOrAroundTheFileIsLive() {
        // A small step of the clock (a time sync, a wake) must not drop a live session.
        for offset in [-0.5, 0, 1.9, 9.9, 10] {
            let processes = [process(4242, started: written.addingTimeInterval(offset))]
            #expect(
                ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: processes),
                "\(offset)")
        }
        let late = [process(4242, started: written.addingTimeInterval(10.5))]
        #expect(!ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: late))
    }

    @Test func withDuplicatePidsOneMatchingProcessIsEnough() {
        let processes = [
            process(4242, started: written.addingTimeInterval(60)),
            process(4242, started: written.addingTimeInterval(-60)),
        ]
        #expect(ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: processes))
        let reused = [
            process(4242, path: "", started: written.addingTimeInterval(-60)),
            process(4242, started: written.addingTimeInterval(60)),
        ]
        #expect(!ClaudeSessionParser.isLive(pid: 4242, fileModified: written, among: reused))
    }
}
