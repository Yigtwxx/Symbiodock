import Foundation
import Testing
@testable import SymbiodockCore

struct ClaudeCompactionReaderTests {
    /// 2026-11-15T20:42:20.696Z
    private let snapshotDate = Date(timeIntervalSince1970: 1_794_775_340.696)
    /// 2026-11-15T20:42:15.381Z
    private let userDate = Date(timeIntervalSince1970: 1_794_775_335.381)

    /// Parsed timestamps and the literals above can differ in the last binary digit.
    private func isSameInstant(_ date: Date?, _ expected: Date) -> Bool {
        guard let date else { return false }
        return abs(date.timeIntervalSince(expected)) < 0.001
    }

    private func isSameInstant(_ mark: CompactionMark?, _ expected: CompactionMark) -> Bool {
        switch (mark, expected) {
        case let (.started(a)?, .started(b)), let (.ended(a)?, .ended(b)):
            return isSameInstant(a, b)
        default:
            return false
        }
    }

    private func tail(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }

    private func snapshot(_ messageID: String, update: Bool = false) -> String {
        #"{"type":"file-history-snapshot","messageId":"\#(messageID)","snapshot":{"messageId":"\#(messageID)","trackedFileBackups":{},"timestamp":"2026-11-15T20:42:20.696Z"},"isSnapshotUpdate":\#(update)}"#
    }

    private func user(_ uuid: String, _ text: String) -> String {
        #"{"type":"user","uuid":"\#(uuid)","timestamp":"2026-11-15T20:42:15.381Z","message":{"role":"user","content":"\#(text)"}}"#
    }

    private func assistant(_ uuid: String) -> String {
        #"{"type":"assistant","uuid":"\#(uuid)","timestamp":"2026-11-15T20:42:17.820Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi"}]}}"#
    }

    private let metadata = [
        #"{"type":"last-prompt","lastPrompt":"hello"}"#,
        #"{"type":"mode","mode":"normal"}"#,
        #"{"type":"permission-mode","permissionMode":"default"}"#,
        #"{"type":"tools-used","tools":[]}"#,
    ]
    private let queued =
        #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-11-15T20:42:30.000Z","content":"later"}"#

    @Test func aSnapshotWhoseMessageIsNotWrittenYetMarksTheStart() {
        let data = tail([user("u1", "hello"), assistant("a1"), snapshot("cmd")] + metadata)
        #expect(isSameInstant(ClaudeCompactionReader.compactionMark(inTail: data), .started(snapshotDate)))
    }

    @Test func aSnapshotFollowedByItsMessageIsANormalPrompt() {
        let data = tail([assistant("a0"), snapshot("p1"), user("p1", "hello")])
        #expect(ClaudeCompactionReader.compactionMark(inTail: data) == nil)
    }

    @Test func aSnapshotWhoseMessageCameFirstIsPassedOver() {
        let data = tail([assistant("a0"), user("p1", "hello"), snapshot("p1")])
        #expect(ClaudeCompactionReader.compactionMark(inTail: data) == nil)
    }

    @Test func snapshotUpdatesArePassedOver() {
        let data = tail([user("u0", "hi"), assistant("a0"), snapshot("cmd"), snapshot("a0", update: true)])
        #expect(isSameInstant(ClaudeCompactionReader.compactionMark(inTail: data), .started(snapshotDate)))
    }

    @Test func metadataAndQueuedMessagesAfterTheMarkDoNotHideIt() {
        let data = tail([assistant("a1"), snapshot("cmd")] + metadata + [queued])
        #expect(isSameInstant(ClaudeCompactionReader.compactionMark(inTail: data), .started(snapshotDate)))
    }

    @Test func theOlderPlainCommandRecordMarksTheStart() {
        // 2.1.303–2.1.318: the `/compact` record first, then its snapshot.
        let data = tail([assistant("a1"), user("c1", "/compact"), snapshot("c1")] + metadata)
        #expect(isSameInstant(ClaudeCompactionReader.compactionMark(inTail: data), .started(userDate)))
    }

    /// 2026-11-15T20:42:38.697Z
    private let boundaryDate = Date(timeIntervalSince1970: 1_794_775_358.697)

    private func boundary(trigger: String) -> String {
        #"{"type":"system","subtype":"compact_boundary","uuid":"b1","timestamp":"2026-11-15T20:42:38.697Z","compactMetadata":{"trigger":"\#(trigger)","preTokens":1000}}"#
    }

    private let summary =
        #"{"type":"user","isCompactSummary":true,"uuid":"s1","timestamp":"2026-11-15T20:42:38.700Z","message":{"role":"user","content":"This session is being continued from a previous conversation"}}"#
    private let caveat =
        #"{"type":"user","isMeta":true,"uuid":"c2","timestamp":"2026-11-15T20:42:38.701Z","message":{"role":"user","content":"<local-command-caveat>Caveat</local-command-caveat>"}}"#
    private let command =
        #"{"type":"user","uuid":"c3","timestamp":"2026-11-15T20:42:38.702Z","message":{"role":"user","content":"<command-name>/compact</command-name>\n<command-message>compact</command-message>\n<command-args></command-args>"}}"#
    private let stdout =
        #"{"type":"user","uuid":"c4","timestamp":"2026-11-15T20:42:38.703Z","message":{"role":"user","content":"<local-command-stdout>Compacted</local-command-stdout>"}}"#
    private let attachment =
        #"{"type":"attachment","uuid":"t1","timestamp":"2026-11-15T20:42:38.800Z","attachment":{"type":"hook"}}"#

    @Test func theRealEndOfAManualCompactionIsAnEnd() {
        let data = tail(
            [assistant("a1"), snapshot("cmd"), boundary(trigger: "manual"), summary, caveat, command,
             stdout, attachment, attachment] + metadata)
        #expect(isSameInstant(ClaudeCompactionReader.compactionMark(inTail: data), .ended(boundaryDate)))
    }

    @Test func anEndCountsForAShortWhileOnly() {
        let end = boundaryDate
        #expect(ClaudeCompactionReader.isCompacting(.ended(end), now: end.addingTimeInterval(0.1)))
        #expect(!ClaudeCompactionReader.isCompacting(.ended(end), now: end.addingTimeInterval(6)))
    }

    @Test func anAutoBoundaryFollowedByAnAssistantRecordIsNothing() {
        let data = tail([boundary(trigger: "auto"), summary, assistant("a2")])
        #expect(ClaudeCompactionReader.compactionMark(inTail: data) == nil)
    }

    @Test func anAutoBoundaryAsTheLastTellingRecordIsNothing() {
        let data = tail([assistant("a1"), boundary(trigger: "auto"), summary, attachment] + metadata)
        #expect(ClaudeCompactionReader.compactionMark(inTail: data) == nil)
    }

    @Test func aNewPromptAfterAManualEndHidesIt() {
        let data = tail(
            [boundary(trigger: "manual"), summary, caveat, command, stdout, user("p2", "hello")])
        #expect(ClaudeCompactionReader.compactionMark(inTail: data) == nil)
    }

    @Test func attachmentsAfterARealPromptAreNothing() {
        let data = tail([assistant("a1"), user("p2", "hello"), attachment, attachment])
        #expect(ClaudeCompactionReader.compactionMark(inTail: data) == nil)
    }

    @Test func brokenLinesAreSkipped() {
        let data = tail(["{\"type\":\"assist", assistant("a1"), snapshot("cmd"), "not json"])
        #expect(isSameInstant(ClaudeCompactionReader.compactionMark(inTail: data), .started(snapshotDate)))
        #expect(ClaudeCompactionReader.compactionMark(inTail: Data()) == nil)
    }

    @Test func aStartCountsOnlyOnceItHasSettled() {
        let start = snapshotDate
        #expect(!ClaudeCompactionReader.isCompacting(.started(start), now: start.addingTimeInterval(0.5)))
        #expect(ClaudeCompactionReader.isCompacting(.started(start), now: start.addingTimeInterval(1)))
        #expect(ClaudeCompactionReader.isCompacting(.started(start), now: start.addingTimeInterval(80)))
    }
}
