# Finish Seal and Compacting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A finished agent session plays a Face ID-style seal on the collapsed island and then lets go of it; a Claude Code session that runs `/compact` shows a purple dashed line around the island, a purple dashed turning ring and a top-to-bottom pet wave until the compaction ends.

**Architecture:** Pure logic in `Packages/SymbiodockCore` (transcript reader, board states and ordering, pet and seal motion), tested with `swift test`. The app target wires the reader into `ClaudeCodeProvider` and draws the new looks: loops in Core Animation, the one-shot seal with a `TimelineView` that stops when the seal is drawn.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Core Animation, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-15-finish-seal-and-compacting-design.md`

## Global Constraints

- Read-only: no hooks, nothing written into any tool's folders, no new dependency, no permission prompt; user content (prompts, titles, transcripts) is never logged.
- No view redraws frame by frame at rest: loops run in Core Animation; the seal redraws only during its 1.15 s of motion.
- The rim light's effect, the line under the notch and the right mark's existing effects (working arc, knocking dot, mint check with ripple) are not changed.
- Purple is `#BF5AF2`; mint `#63E6A9` and amber `#FFD60A` stay as they are.
- Code, identifiers and comments in English; UI text in English.
- After each task: `swift test --package-path Packages/SymbiodockCore` passes, and from Task 2 on the app builds:
  `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3` ends with `** BUILD SUCCEEDED **`.
- Commits: Conventional Commits, title ≤ 72 characters, imperative, body says why; end every message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01BW1DAFBgzicFoQakMEsPVS`. Push to `main` after each task (`git push origin main`). Never force-push.
- This plan was written without compiling. If plan code does not compile, fix it keeping the behaviour and the interfaces, and update this plan in the same commit.

---

### Task 1: Read the compaction mark from a transcript

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/ClaudeCompactionReader.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/ClaudeCompactionReaderTests.swift`

**Interfaces:**
- Produces: `ClaudeCompactionReader.tailSize: Int` (64 KB), `ClaudeCompactionReader.settleTime: TimeInterval` (1), `ClaudeCompactionReader.compactionStart(inTail: Data) -> Date?`, `ClaudeCompactionReader.isCompacting(start: Date, now: Date) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct ClaudeCompactionReaderTests {
    /// 2026-11-15T20:42:20.696Z
    private let snapshotDate = Date(timeIntervalSince1970: 1_794_775_340.696)
    /// 2026-11-15T20:42:15.381Z
    private let userDate = Date(timeIntervalSince1970: 1_794_775_335.381)

    private func tail(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }

    /// Parsed timestamps and the literals above can differ in the last binary digit.
    private func isSameInstant(_ date: Date?, _ expected: Date) -> Bool {
        guard let date else { return false }
        return abs(date.timeIntervalSince(expected)) < 0.001
    }

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
    private let boundary =
        #"{"type":"system","subtype":"compact_boundary","uuid":"b1","timestamp":"2026-11-15T20:42:38.697Z"}"#

    @Test func aSnapshotWhoseMessageIsNotWrittenYetMarksTheStart() {
        let data = tail([user("u1", "hello"), assistant("a1"), snapshot("cmd")] + metadata)
        #expect(isSameInstant(ClaudeCompactionReader.compactionStart(inTail: data), snapshotDate))
    }

    @Test func aSnapshotFollowedByItsMessageIsANormalPrompt() {
        let data = tail([assistant("a0"), snapshot("p1"), user("p1", "hello")])
        #expect(ClaudeCompactionReader.compactionStart(inTail: data) == nil)
    }

    @Test func aSnapshotWhoseMessageCameFirstIsPassedOver() {
        let data = tail([assistant("a0"), user("p1", "hello"), snapshot("p1")])
        #expect(ClaudeCompactionReader.compactionStart(inTail: data) == nil)
    }

    @Test func snapshotUpdatesArePassedOver() {
        let data = tail([user("u0", "hi"), assistant("a0"), snapshot("cmd"), snapshot("a0", update: true)])
        #expect(isSameInstant(ClaudeCompactionReader.compactionStart(inTail: data), snapshotDate))
    }

    @Test func metadataAndQueuedMessagesAfterTheMarkDoNotHideIt() {
        let data = tail([assistant("a1"), snapshot("cmd")] + metadata + [queued])
        #expect(isSameInstant(ClaudeCompactionReader.compactionStart(inTail: data), snapshotDate))
    }

    @Test func theOlderPlainCommandRecordMarksTheStart() {
        // 2.1.303–2.1.318: the `/compact` record first, then its snapshot.
        let data = tail([assistant("a1"), user("c1", "/compact"), snapshot("c1")] + metadata)
        #expect(isSameInstant(ClaudeCompactionReader.compactionStart(inTail: data), userDate))
    }

    @Test func aFinishedCompactionIsNoStart() {
        let caveat = user("c2", "<local-command-caveat>Caveat</local-command-caveat>")
        let data = tail([assistant("a1"), snapshot("cmd"), boundary, caveat])
        #expect(ClaudeCompactionReader.compactionStart(inTail: data) == nil)
    }

    @Test func brokenLinesAreSkipped() {
        let data = tail(["{\"type\":\"assist", assistant("a1"), snapshot("cmd"), "not json"])
        #expect(isSameInstant(ClaudeCompactionReader.compactionStart(inTail: data), snapshotDate))
        #expect(ClaudeCompactionReader.compactionStart(inTail: Data()) == nil)
    }

    @Test func aStartCountsOnlyOnceItHasSettled() {
        let start = snapshotDate
        #expect(!ClaudeCompactionReader.isCompacting(start: start, now: start.addingTimeInterval(0.5)))
        #expect(ClaudeCompactionReader.isCompacting(start: start, now: start.addingTimeInterval(1)))
        #expect(ClaudeCompactionReader.isCompacting(start: start, now: start.addingTimeInterval(80)))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter ClaudeCompactionReaderTests`
Expected: compile error, `cannot find 'ClaudeCompactionReader' in scope`.

- [ ] **Step 3: Write the reader**

```swift
import Foundation

/// Tells from the end of a Claude Code transcript whether a manual `/compact` is under way.
/// Claude Code writes the records that describe a compaction when it ends; its start leaves
/// one mark: a file snapshot whose message is not written yet (2.1.325), or a plain
/// `/compact` user record (2.1.303–2.1.318). Spec:
/// `2026-11-15-finish-seal-and-compacting-design.md`, section 5.1.
public enum ClaudeCompactionReader {
    /// How much of the transcript's end is read; the mark is always among the last records.
    public static let tailSize = 64 * 1024
    /// How old a mark must be before it counts: a normal prompt's snapshot is followed by
    /// its user record within milliseconds.
    public static let settleTime: TimeInterval = 1

    /// The record types that say something about the conversation. Every other type
    /// (metadata, queue operations, types added later) is passed over.
    private static let telling: Set<String> = [
        "user", "assistant", "system", "attachment", "file-history-snapshot",
    ]

    /// When the compaction under way started; nil when the tail shows none. Walks the lines
    /// from the end; lines that are cut off or are not JSON are skipped.
    public static func compactionStart(inTail data: Data) -> Date? {
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String, telling.contains(type)
            else { continue }
            switch type {
            case "file-history-snapshot":
                // An update rewrites an older snapshot; it says nothing about a new message.
                if object["isSnapshotUpdate"] as? Bool == true { continue }
                guard let messageID = object["messageId"] as? String, !messageID.isEmpty else {
                    return nil
                }
                // Its message is already written: an ordinary snapshot.
                if mentions(uuid: messageID, in: data) { continue }
                guard let snapshot = object["snapshot"] as? [String: Any],
                      let stamp = snapshot["timestamp"] as? String
                else { return nil }
                return timestamp(stamp)
            case "user":
                guard let message = object["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/compact"),
                      let stamp = object["timestamp"] as? String
                else { return nil }
                return timestamp(stamp)
            default:
                return nil
            }
        }
        return nil
    }

    /// Whether a compaction that started at `start` counts at `now`.
    public static func isCompacting(start: Date, now: Date) -> Bool {
        now.timeIntervalSince(start) >= settleTime
    }

    /// Whether a record in the tail has this uuid. Claude Code writes compact JSON, so the
    /// key and its value sit side by side.
    private static func mentions(uuid: String, in data: Data) -> Bool {
        data.range(of: Data("\"uuid\":\"\(uuid)\"".utf8)) != nil
    }

    /// "2026-11-15T20:42:20.696Z", with or without the fraction.
    private static func timestamp(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path Packages/SymbiodockCore --filter ClaudeCompactionReaderTests`
Expected: all 9 tests pass. Then the whole suite: `swift test --package-path Packages/SymbiodockCore` passes.

- [ ] **Step 5: Commit and push**

```bash
git add Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/ClaudeCompactionReader.swift Packages/SymbiodockCore/Tests/SymbiodockCoreTests/ClaudeCompactionReaderTests.swift
git commit -m "feat(agents): read a running compaction from the transcript

Claude Code keeps compaction state in its process only; the mark its start
leaves in the transcript lets the island show it without a hook."
git push origin main
```

---

### Task 2: A compacting state, and `shell` as idle

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSession.swift` (`AgentActivity`)
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSessionBoard.swift` (`AgentRowState`, `update`, `attention`, `lead`, `state(of:)`)
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentBranches.swift:94-99` (`isActive`)
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentLabels.swift:13-22` (`status`)
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/ClaudeSessionParser.swift:78-92` (`session(from:...)`)
- Modify (app, exhaustive switches): `Symbiodock/Island/Agents/AgentPalette.swift`, `Symbiodock/Island/Agents/AgentStatusMark.swift`, `Symbiodock/Island/Agents/AgentFaces.swift`, `Symbiodock/Island/Agents/AgentsContent.swift`, `Symbiodock/Island/Agents/AgentPet.swift`, `Symbiodock/App/DebugRender.swift`
- Test: `AgentSessionBoardTests.swift`, `ClaudeSessionParserTests.swift`, `AgentLabelsTests.swift` (all in `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/`)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `AgentActivity.compacting`, `AgentRowState.compacting`, `ClaudeSessionParser.session(from: ClaudeSessionRecord, prompt: String?, compacting: Bool = false, fallbackSince: Date) -> AgentSession?`, `AgentPalette.compacting: Color`.

- [ ] **Step 1: Write the failing tests**

Add to `AgentSessionBoardTests` (it has `session(_ id:, _ activity:, since:)`):

```swift
    @Test func aCompactingSessionLeadsLikeAWorkingOne() {
        var board = AgentSessionBoard()
        board.update([session("idle", .idle), session("c", .compacting)])
        #expect(board.rows.map(\.id) == ["c", "idle"])
        #expect(board.lead?.id == "c")
        #expect(board.lead?.state == .compacting)
        #expect(board.hasFace)
        #expect(board.attention == .none)
    }

    @Test func aCompactionThatEndsIsNotAFinish() {
        var board = AgentSessionBoard()
        board.update([session("c", .compacting)])
        board.update([session("c", .idle, since: 5)])
        #expect(board.rows.map(\.state) == [.idle])
        #expect(board.attention == .none)
    }

    @Test func aCompactionSeenLateAfterWorkingIsNotAFinish() {
        // The first scans of a compaction show it as working (spec 5.1).
        var board = AgentSessionBoard()
        board.update([session("c", .working)])
        board.update([session("c", .compacting, since: 3)])
        board.update([session("c", .idle, since: 5)])
        #expect(board.rows.map(\.state) == [.idle])
    }

    @Test func compactingClearsAFinish() {
        var board = AgentSessionBoard()
        board.update([session("c", .working)])
        board.update([session("c", .idle, since: 5)])
        #expect(board.rows.map(\.state) == [.finished])
        board.update([session("c", .compacting, since: 9)])
        #expect(board.rows.map(\.state) == [.compacting])
        board.update([session("c", .idle, since: 12)])
        #expect(board.rows.map(\.state) == [.idle])
    }

    @Test func aMessageQueuedDuringACompactionFinishesNormally() {
        var board = AgentSessionBoard()
        board.update([session("c", .compacting)])
        board.update([session("c", .working, since: 5)])
        board.update([session("c", .idle, since: 9)])
        #expect(board.rows.map(\.state) == [.finished])
    }
```

Add to `ClaudeSessionParserTests` (it has `data(_:)` and `fallback`):

```swift
    @Test func aBusySessionThatCompactsIsCompacting() throws {
        let busy = try #require(ClaudeSessionParser.record(from: data("{\"pid\":1,\"status\":\"busy\"}")))
        #expect(
            ClaudeSessionParser.session(from: busy, prompt: nil, compacting: true, fallbackSince: fallback)?
                .activity == .compacting)
        // Only a busy session compacts.
        let idle = try #require(ClaudeSessionParser.record(from: data("{\"pid\":1,\"status\":\"idle\"}")))
        #expect(
            ClaudeSessionParser.session(from: idle, prompt: nil, compacting: true, fallbackSince: fallback)?
                .activity == .idle)
    }

    @Test func aTurnThatEndedWithABackgroundShellIsIdle() {
        #expect(session("{\"pid\":1,\"status\":\"shell\"}")?.activity == .idle)
    }
```

Add to `AgentLabelsTests`:

```swift
    @Test func aCompactingSessionSaysSo() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(AgentLabels.status(.compacting, since: start, now: start.addingTimeInterval(300)) == "Compacting")
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: compile errors, `type 'AgentActivity' has no member 'compacting'` and `extra argument 'compacting' in call`.

- [ ] **Step 3: Add the state to the core**

In `AgentSession.swift`, add to `AgentActivity` after `case working`:

```swift
    /// Compacting its conversation (`/compact`): busy, but not on a turn of its own, so its
    /// end is not a finish.
    case compacting
```

In `AgentSessionBoard.swift`:

```swift
public enum AgentRowState: Equatable, Sendable {
    case needsInput(prompt: String?)
    case working
    case compacting
    case finished
    case running
    case idle

    /// Lower sorts first.
    var rank: Int {
        switch self {
        case .needsInput: 0
        case .working, .compacting: 1
        case .finished: 2
        case .running: 3
        case .idle: 4
        }
    }
}
```

In `update(_:)`, add a case to the `switch session.activity` (between `.working, .needsInput` and `.idle`):

```swift
            case .compacting:
                // Not a turn: what showed as finished is not, and its end will not be.
                finishedIDs.remove(session.id)
```

In `attention`, change `case .working, .running, .idle: break` to `case .working, .compacting, .running, .idle: break`.
In `lead`, change `case .needsInput, .working, .finished: return first` to `case .needsInput, .working, .compacting, .finished: return first`.
In `state(of:)`, add `case .compacting: .compacting` after `case .working: .working`.

In `AgentBranches.swift` `isActive`, change `case .finished, .running, .idle: false` to `case .compacting, .finished, .running, .idle: false`.

In `AgentLabels.swift` `status`, add after the `.working` line:

```swift
        case .compacting: return "Compacting"
```

In `ClaudeSessionParser.swift`, replace the `session(from:prompt:fallbackSince:)` signature, doc and status switch:

```swift
    /// The session a record stands for; nil for a spare process.
    /// - Parameter prompt: the open question, if one was read from the transcript.
    /// - Parameter compacting: whether the transcript shows a compaction under way; counts
    ///   only while the session is busy.
    /// - Parameter fallbackSince: used when the file does not say when the status began.
    public static func session(
        from record: ClaudeSessionRecord, prompt: String?, compacting: Bool = false,
        fallbackSince: Date
    ) -> AgentSession? {
        guard !record.isSpare else { return nil }
        let activity: AgentActivity =
            switch record.status {
            case "busy": compacting ? .compacting : .working
            // "shell": the turn is over while a background shell command still runs
            // (seen with 2.1.325); the session waits for the user like an idle one.
            case "idle", "shell": .idle
            case "waiting": .needsInput(prompt: prompt)
            default: .running
            }
```

(Keep the rest of the function as it is.) Update the `status` field's doc comment at the top of the file from `"busy", "idle", "waiting", or something newer.` to `"busy", "idle", "waiting", "shell", or something newer.`

- [ ] **Step 4: Run the core tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: all pass.

- [ ] **Step 5: Make the app's switches exhaustive**

`Symbiodock/Island/Agents/AgentPalette.swift`, after `mint`:

```swift
    /// A session compacts its conversation. #BF5AF2, purple: apart from the tool colours,
    /// the mint and the amber.
    static let compacting = Color(red: 191.0 / 255.0, green: 90.0 / 255.0, blue: 242.0 / 255.0)
```

`Symbiodock/Island/Agents/AgentStatusMark.swift`: in `color` add `case .compacting: AgentPalette.compacting`; in `accessibilityText` add `case .compacting: "Compacting"`.

`Symbiodock/Island/Agents/AgentFaces.swift` (`AgentFaceLabel.text`): add `case .compacting: "Compacting"`.

`Symbiodock/Island/Agents/AgentsContent.swift` (`labelColor`): add `case .compacting: AgentPalette.compacting`.

`Symbiodock/Island/Agents/AgentPet.swift` (`strength`): change `case .working, .needsInput, .finished: 1` to `case .working, .compacting, .needsInput, .finished: 1`.

`Symbiodock/App/DebugRender.swift` (`CollapsedGallery.row`): add `case .compacting: board.update([session(.compacting)])`.

- [ ] **Step 6: Build the app**

Run: `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. If a switch elsewhere is reported non-exhaustive, add the `.compacting` case next to `.working` (same look) and list the file in the commit.

- [ ] **Step 7: Commit and push**

```bash
git add -A Packages/SymbiodockCore Symbiodock
git commit -m "feat(agents): add a compacting state and read shell as idle

A compaction is busy but not a turn, so its end must not count as a finish.
Claude Code writes shell when a turn ends with a background command open,
which hid the finish."
git push origin main
```

---

### Task 3: Settle a finish; finishes lead until they settle

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSessionBoard.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentSessionBoardTests.swift`, `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandStateTests.swift`

**Interfaces:**
- Consumes: `AgentRowState.compacting` (Task 2).
- Produces: `AgentRow.isSettled: Bool`, `AgentSessionBoard.settle(_ id: String)`, `IslandState.settleFinished(_ id: String)`, `IslandState.sealingID: String?`, `IslandState.showsCompactingRim: Bool`.

- [ ] **Step 1: Write the failing tests**

In `AgentSessionBoardTests`, replace `aFinishedRowIsFoundBehindAWorkingOne` (the order changes on purpose, spec 4.2) with:

```swift
    @Test func anUnsettledFinishLeadsBeforeAWorkingOne() {
        var board = AgentSessionBoard()
        board.update([session("done", .working), session("busy", .working, since: 5)])
        board.update([session("done", .idle), session("busy", .working, since: 5)])
        #expect(board.rows.map(\.id) == ["done", "busy"])
        #expect(board.lead?.id == "done")
        #expect(board.attention == .finished)
        #expect(board.attentionRow?.id == "done")
        #expect(board.attentionRow?.state == .finished)
    }

    @Test func aSettledFinishStepsBehindTheWorkingOnes() {
        var board = AgentSessionBoard()
        board.update([session("done", .working), session("busy", .working, since: 5)])
        board.update([session("done", .idle), session("busy", .working, since: 5)])
        board.settle("done")
        #expect(board.rows.map(\.id) == ["busy", "done"])
        #expect(board.lead?.id == "busy")
        #expect(board.attention == .none)
        #expect(board.attentionRow == nil)
    }

    @Test func aSettledFinishStaysDoneButNoLongerSpeaks() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        board.update([session("a", .idle, since: 5)])
        board.settle("a")
        #expect(board.rows.map(\.state) == [.finished])
        #expect(board.rows.first?.isSettled == true)
        #expect(board.lead == nil)
        #expect(board.attention == .none)
        #expect(!board.hasFace)
    }

    @Test func settlingWhatIsNotFinishedDoesNothing() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        let before = board
        board.settle("a")
        board.settle("nobody")
        #expect(board == before)
    }

    @Test func markSeenForgetsSettledFinishes() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        board.update([session("a", .idle, since: 5)])
        board.settle("a")
        board.markSeen()
        #expect(board.rows.map(\.state) == [.idle])
        #expect(board.rows.first?.isSettled == false)
    }

    @Test func workingAgainForgetsTheSettledMark() {
        var board = AgentSessionBoard()
        board.update([session("a", .working)])
        board.update([session("a", .idle, since: 5)])
        board.settle("a")
        board.update([session("a", .working, since: 9)])
        board.update([session("a", .idle, since: 12)])
        #expect(board.rows.map(\.state) == [.finished])
        #expect(board.rows.first?.isSettled == false)
        #expect(board.lead?.id == "a")
    }

    @Test func finishesSettleOneAfterAnother() {
        var board = AgentSessionBoard()
        board.update([session("a", .working), session("b", .working)])
        board.update([session("a", .idle, since: 5), session("b", .idle, since: 9)])
        #expect(board.attentionRow?.id == "b")
        board.settle("b")
        #expect(board.attentionRow?.id == "a")
        board.settle("a")
        #expect(board.attentionRow == nil)
        #expect(board.rows.map(\.state) == [.finished, .finished])
    }

    @Test func aFinishOutranksACompaction() {
        var board = AgentSessionBoard()
        board.update([session("a", .working), session("c", .compacting)])
        board.update([session("a", .idle, since: 5), session("c", .compacting)])
        #expect(board.lead?.id == "a")
        board.settle("a")
        #expect(board.lead?.id == "c")
    }
```

In `IslandStateTests` (it has `agent(_:_:)` and `track(playing:)`):

```swift
    @Test func settlingAFinishClosesTheWings() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.sealingID == "a")
        #expect(state.showsWings)
        state.settleFinished("a")
        #expect(state.sealingID == nil)
        #expect(!state.showsWings)
        #expect(state.board.rows.first?.state == .finished)
    }

    @Test func noSealPlaysWhileTheIslandIsOpen() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(true)
        #expect(state.sealingID == nil)
    }

    @Test func theMediaFaceAlsoSealsAFinish() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.face == .media)
        #expect(state.sealingID == "a")
    }

    @Test func theCompactingRimShowsWhileTheAgentsFaceCompacts() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .compacting)])
        #expect(state.showsCompactingRim)
        state.setHovering(true)
        #expect(!state.showsCompactingRim)
        state.setHovering(false)
        state.setAgentSessions([agent("a", .idle)])
        #expect(!state.showsCompactingRim)
    }

    @Test func theCompactingRimWaitsBehindAFinish() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working), agent("b", .compacting)])
        state.setAgentSessions([agent("a", .idle), agent("b", .compacting)])
        #expect(!state.showsCompactingRim)
        state.settleFinished("a")
        #expect(state.showsCompactingRim)
    }

    @Test func theMediaFaceShowsNoCompactingRim() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .compacting)])
        #expect(state.face == .media)
        #expect(!state.showsCompactingRim)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: compile errors, `value of type 'AgentSessionBoard' has no member 'settle'`.

- [ ] **Step 3: Implement settling in the board**

In `AgentSessionBoard.swift`, replace `AgentRowState.rank` with an order that knows about settling:

```swift
    /// Lower sorts first. A finish leads until it has played its seal (`settled`), then it
    /// steps back behind the sessions that are still at work.
    func rank(settled: Bool) -> Int {
        switch self {
        case .needsInput: 0
        case .finished: settled ? 3 : 1
        case .working, .compacting: 2
        case .running: 4
        case .idle: 5
        }
    }
```

Add `isSettled` to `AgentRow`, after `state`:

```swift
    /// A finish that has played its seal: still `Done ✓` in the list, but it no longer
    /// leads the collapsed island or draws attention. Always false for other states.
    public let isSettled: Bool
```

Add to `AgentSessionBoard`, after `finishedIDs`:

```swift
    /// Finished sessions whose seal has played; always a subset of `finishedIDs`.
    private var settledIDs: Set<String> = []
```

In `update(_:)`, make each case clear or keep the settled mark:

```swift
            switch session.activity {
            case .working, .needsInput:
                active.insert(session.id)
                finishedIDs.remove(session.id)
                settledIDs.remove(session.id)
                if !activeIDs.contains(session.id) || turnStarts[session.id] == nil {
                    turnStarts[session.id] = session.since
                }
            case .compacting:
                // Not a turn: what showed as finished is not, and its end will not be.
                finishedIDs.remove(session.id)
                settledIDs.remove(session.id)
            case .idle:
                if activeIDs.contains(session.id) { finishedIDs.insert(session.id) }
            case .running:
                finishedIDs.remove(session.id)
                settledIDs.remove(session.id)
            }
```

and after `finishedIDs.formIntersection(seen)` add `settledIDs.formIntersection(finishedIDs)`.

Add the method after `markSeen()`, and make `markSeen()` clear both sets:

```swift
    /// Forgets every finished mark: the user has looked.
    public mutating func markSeen() {
        guard !finishedIDs.isEmpty else { return }
        finishedIDs.removeAll()
        settledIDs.removeAll()
        rebuild(from: rows.map(\.session))
    }

    /// A finished session has played its seal: it stays `Done ✓` in the list until
    /// `markSeen`, but no longer leads, draws attention or gives the island a face.
    /// Ignored for a session that is not finished, or already settled.
    public mutating func settle(_ id: String) {
        guard finishedIDs.contains(id), settledIDs.insert(id).inserted else { return }
        rebuild(from: rows.map(\.session))
    }
```

Replace `attention`, `lead` and `attentionRow`:

```swift
    public var attention: AgentAttention {
        var result = AgentAttention.none
        for row in rows {
            switch row.state {
            case .needsInput: return .needsInput
            case .finished where !row.isSettled: result = .finished
            case .working, .compacting, .finished, .running, .idle: break
            }
        }
        return result
    }

    /// The session the collapsed island speaks for, if any deserves it.
    public var lead: AgentRow? {
        guard let first = rows.first else { return nil }
        switch first.state {
        case .needsInput, .working, .compacting: return first
        case .finished: return first.isSettled ? nil : first
        case .running, .idle: return nil
        }
    }
```

```swift
    public var attentionRow: AgentRow? {
        rows.first { if case .needsInput = $0.state { true } else { false } }
            ?? rows.first { $0.state == .finished && !$0.isSettled }
    }
```

Update the doc comment of `attentionRow` to: `/// The session behind `attention`: the first that needs input, else the first finish that has not settled.`

In `rebuild(from:)`:

```swift
    private mutating func rebuild(from sessions: [AgentSession]) {
        rows = sessions
            .map { session in
                let state = state(of: session)
                return AgentRow(
                    session: session, state: state,
                    isSettled: state == .finished && settledIDs.contains(session.id),
                    branches: AgentBranches.lines(
                        for: session.subagents, state: state, turnStart: turnStarts[session.id]))
            }
            .sorted { lhs, rhs in
                let left = lhs.state.rank(settled: lhs.isSettled)
                let right = rhs.state.rank(settled: rhs.isSettled)
                if left != right { return left < right }
                if lhs.session.since != rhs.session.since {
                    return lhs.session.since > rhs.session.since
                }
                return lhs.id < rhs.id
            }
    }
```

Run `grep -rn "\.rank\b\|AgentRow(" Packages Symbiodock --include='*.swift'` and update any other use to `rank(settled:)` / the new initialiser.

- [ ] **Step 4: Add the state's API**

In `IslandState.swift`, after `setAgentSessions(_:)`:

```swift
    /// The seal of a finished session has played: it stops leading the collapsed island.
    public func settleFinished(_ id: String) {
        var next = board
        next.settle(id)
        // Assign only on change: every assignment redraws the island.
        if next != board { board = next }
    }

    /// The finished session whose seal the collapsed island plays, if any: while the island
    /// is collapsed and a finish is the most urgent thing it shows. On the media face the
    /// seal is the mark's check alone.
    public var sealingID: String? {
        guard phase == .collapsed, board.attention == .finished else { return nil }
        return board.attentionRow?.id
    }

    /// Whether the collapsed island draws the dashed compacting line around itself: the
    /// session the agents face speaks for is compacting.
    public var showsCompactingRim: Bool {
        phase == .collapsed && face == .agents && board.lead?.state == .compacting
    }
```

- [ ] **Step 5: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: all pass. If an older test fails only because an unsettled finish now sorts before a working row, fix its expectation and name the test in the commit body; any other failure is a bug.

- [ ] **Step 6: Build the app**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit and push**

```bash
git add -A Packages/SymbiodockCore
git commit -m "feat(agents): settle a finish once its seal has played

The owner wants the island to let go after the seal while the list keeps
Done until the tab is opened; a finish leads meanwhile so its seal plays on
the face even while another session works."
git push origin main
```

---

### Task 4: Motion for the downward wave and the seal

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentPetFigure.swift` (`AgentPetMotion`)
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSealTiming.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentPetDownWaveTests.swift`, `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentSealTimingTests.swift`

**Interfaces:**
- Produces: `AgentPetMotion.downBand: Double`, `AgentPetMotion.downCrestRange: ClosedRange<Double>`, `AgentPetMotion.downCrest(at: TimeInterval) -> Double?`, `AgentPetMotion.waveDown(y: Double, at: TimeInterval) -> Double`; `AgentSealTiming.duration`, `.stillDuration`, `.framed`, `.rounded`, `.checked`, `AgentSealTiming.Pose { frameScale, roundness, petOpacity, petScale, mint, check, swell }`, `AgentSealTiming.pose(at:) -> Pose`, `AgentSealTiming.finalPose`.

- [ ] **Step 1: Write the failing tests**

`AgentPetDownWaveTests.swift`:

```swift
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
```

`AgentSealTimingTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct AgentSealTimingTests {
    @Test func thePhasesFitTheDuration() {
        #expect(0 < AgentSealTiming.framed)
        #expect(AgentSealTiming.framed < AgentSealTiming.rounded)
        #expect(AgentSealTiming.rounded < AgentSealTiming.checked)
        #expect(AgentSealTiming.checked < AgentSealTiming.duration)
        #expect(AgentSealTiming.stillDuration < AgentSealTiming.duration)
    }

    @Test func itStartsWithAWideFrameAroundAWholePet() {
        let pose = AgentSealTiming.pose(at: 0)
        #expect(pose.frameScale == AgentSealTiming.frameStart)
        #expect(pose.roundness == 0)
        #expect(pose.petOpacity == 1)
        #expect(pose.petScale == 1)
        #expect(pose.mint == 0)
        #expect(pose.check == 0)
        #expect(pose.swell == 1)
    }

    @Test func theFrameClosesOnThePetBeforeItRounds() {
        let pose = AgentSealTiming.pose(at: AgentSealTiming.framed)
        #expect(pose.frameScale == 1)
        #expect(pose.roundness == 0)
        #expect(pose.petOpacity == 1)
    }

    @Test func thePetIsGoneOnceTheFrameIsRound() {
        let pose = AgentSealTiming.pose(at: AgentSealTiming.rounded)
        #expect(pose.roundness == 1)
        #expect(pose.petOpacity == 0)
        #expect(abs(pose.petScale - (1 - AgentSealTiming.petShrink)) < 1e-9)
        #expect(pose.check == 0)
    }

    @Test func itEndsAsAMintCircleWithACheck() {
        for time in [AgentSealTiming.checked, AgentSealTiming.duration] {
            let pose = AgentSealTiming.pose(at: time)
            #expect(pose.mint == 1)
            #expect(pose.check == 1)
            #expect(abs(pose.swell - 1) < 1e-9)
        }
    }

    @Test func theCircleSwellsWhileTheCheckLands() {
        let middle = (AgentSealTiming.rounded + AgentSealTiming.checked) / 2
        #expect(abs(AgentSealTiming.pose(at: middle).swell - (1 + AgentSealTiming.pop)) < 1e-9)
    }

    @Test func timeOutsideTheSealIsClamped() {
        #expect(AgentSealTiming.pose(at: -1) == AgentSealTiming.pose(at: 0))
        #expect(AgentSealTiming.pose(at: 10) == AgentSealTiming.finalPose)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: compile errors, `type 'AgentPetMotion' has no member 'downCrest'`, `cannot find 'AgentSealTiming' in scope`.

- [ ] **Step 3: Add the downward wave to `AgentPetMotion`**

Inside `public enum AgentPetMotion` in `AgentPetFigure.swift`, after `wave(column:at:)`:

```swift
    /// How tall the crest of the downward wave is, as a share of the pet's height: as many
    /// lines' worth as the crest across is wide.
    public static let downBand = waveWidth / Double(AgentPetFigure.lineCount)
    /// Where the downward crest's centre is when it enters (above the pet) and when it
    /// leaves (below it), as shares of the pet's height from its top.
    public static let downCrestRange: ClosedRange<Double> = (-downBand / 2)...(1 + downBand / 2)

    /// Where the centre of the downward crest is at `time`, as a share of the pet's height
    /// from its top; nil while the pet rests. A compacting pet's wave: the period and pace
    /// of the wave across, running from top to bottom. It moves at an even pace, so two
    /// keyframes (entry and exit) describe it exactly.
    public static func downCrest(at time: TimeInterval) -> Double? {
        var beat = time.truncatingRemainder(dividingBy: wavePeriod)
        if beat < 0 { beat += wavePeriod }
        guard beat < waveTravel else { return nil }
        let span = downCrestRange.upperBound - downCrestRange.lowerBound
        return downCrestRange.lowerBound + span * beat / waveTravel
    }

    /// How far forward the part of the pet at height `y` (0 top, 1 bottom) is at `time`:
    /// 0 at rest, 1 at the crest; the same raised cosine as the wave across.
    public static func waveDown(y: Double, at time: TimeInterval) -> Double {
        guard let crest = downCrest(at: time) else { return 0 }
        let distance = abs(y - crest)
        guard distance < downBand / 2 else { return 0 }
        return 0.5 * (1 + cos(2 * .pi * distance / downBand))
    }
```

- [ ] **Step 4: Add `AgentSealTiming`**

```swift
import Foundation

/// The finish seal: a finished session's pet is framed the way Face ID frames a face, the
/// frame closes into a circle as the pet fades, and a check is drawn in the circle. Pure
/// functions of time, so the views only draw. Spec:
/// `2026-11-15-finish-seal-and-compacting-design.md`, section 4.1.
public enum AgentSealTiming {
    /// The whole seal; the session settles when it is over.
    public static let duration: TimeInterval = 1.7
    /// How long the still seal shows with Reduce Motion.
    public static let stillDuration: TimeInterval = 1.0
    /// The frame has closed in on the pet.
    public static let framed: TimeInterval = 0.45
    /// The frame has become a circle and the pet has gone.
    public static let rounded: TimeInterval = 0.75
    /// The check is drawn; the seal holds from here until `duration`.
    public static let checked: TimeInterval = 1.15

    /// How large the frame starts, relative to the pet.
    public static let frameStart = 1.25
    /// How much the pet shrinks while it fades.
    public static let petShrink = 0.10
    /// How much the circle swells while the check lands.
    public static let pop = 0.08

    /// One moment of the seal.
    public struct Pose: Equatable, Sendable {
        /// The frame's side relative to the pet's.
        public var frameScale: Double
        /// 0: four corner brackets; 1: a closed circle.
        public var roundness: Double
        public var petOpacity: Double
        public var petScale: Double
        /// 0: the frame is white; 1: it is mint.
        public var mint: Double
        /// How much of the check is drawn, 0...1.
        public var check: Double
        /// The frame and check's scale: 1, swelling a little while the check lands.
        public var swell: Double
    }

    /// The seal `time` seconds after it began. Before 0 it is at its start; from `checked`
    /// on it is at its end.
    public static func pose(at time: TimeInterval) -> Pose {
        let closing = ease(progress(time, from: 0, to: framed))
        let rounding = ease(progress(time, from: framed, to: rounded))
        let checking = progress(time, from: rounded, to: checked)
        return Pose(
            frameScale: frameStart - (frameStart - 1) * closing,
            roundness: rounding,
            petOpacity: 1 - rounding,
            petScale: 1 - petShrink * rounding,
            mint: ease(min(checking * 2, 1)),
            check: ease(checking),
            swell: 1 + pop * sin(.pi * checking))
    }

    /// The seal as it ends: what Reduce Motion shows, still.
    public static var finalPose: Pose { pose(at: checked) }

    private static func progress(_ time: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        min(max((time - start) / (end - start), 0), 1)
    }

    /// Starts and ends gently.
    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: all pass.

- [ ] **Step 6: Commit and push**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(agents): add motion for the downward wave and the finish seal

Both looks are sampled from tested formulas, as every other motion on the
island is."
git push origin main
```

---

### Task 5: Detect compaction in the Claude Code provider

**Files:**
- Modify: `Symbiodock/Agents/ClaudeCodeProvider.swift`

**Interfaces:**
- Consumes: `ClaudeCompactionReader` (Task 1), `ClaudeSessionParser.session(from:prompt:compacting:fallbackSince:)` (Task 2).

- [ ] **Step 1: Cache the start per transcript**

After the `Ends` struct add:

```swift
    /// When a busy session's transcript showed its compaction starting, as of the
    /// transcript's stamp. The start is kept, not the verdict: the transcript does not
    /// change while a compaction runs, and a start counts only once it has settled.
    private struct Compaction {
        let stamp: FileStamp
        let start: Date?
    }
```

Add `var compactions: [String: Compaction] = [:]` to `Kept`, a stored property `private var compactions: [String: Compaction] = [:]` next to `ends`, `compactions.removeAll()` in the `guard let files` failure branch, and `compactions = kept.compactions` in the `defer`.

- [ ] **Step 2: Ask the transcript only while busy**

In `sessions(in:)`, replace the `ClaudeSessionParser.session(...)` call with:

```swift
                  var session = ClaudeSessionParser.session(
                      from: record,
                      prompt: record.status == "waiting"
                          ? question(of: record, remembering: &kept.asked) : nil,
                      compacting: record.status == "busy"
                          && isCompacting(record, now: context.now, remembering: &kept.compactions),
                      fallbackSince: stamp.modified)
```

Add after `question(of:remembering:)`:

```swift
    /// Whether a busy session is compacting its conversation, read from its transcript's
    /// end (see `ClaudeCompactionReader`). The transcript is read again only when its size
    /// or modification time changed.
    private func isCompacting(
        _ record: ClaudeSessionRecord, now: Date, remembering kept: inout [String: Compaction]
    ) -> Bool {
        guard let cwd = record.cwd, let sessionID = record.sessionID,
              let path = ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
        else { return false }
        let url = home.appendingPathComponent(path)
        guard let stamp = FileReading.stamp(of: url) else { return false }
        let start: Date?
        if let known = compactions[path], known.stamp == stamp {
            start = known.start
        } else {
            start = FileReading.tail(of: url, maxBytes: ClaudeCompactionReader.tailSize)
                .flatMap(ClaudeCompactionReader.compactionStart(inTail:))
        }
        kept[path] = Compaction(stamp: stamp, start: start)
        return start.map { ClaudeCompactionReader.isCompacting(start: $0, now: now) } ?? false
    }
```

Update the type's doc comment: append `While a session is busy, the end of its transcript tells whether it is compacting.`

- [ ] **Step 3: Build and test**

Run: `swift test --package-path Packages/SymbiodockCore` then the build command.
Expected: tests pass, `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit and push**

```bash
git add Symbiodock/Agents/ClaudeCodeProvider.swift
git commit -m "feat(agents): show when a Claude Code session compacts

The provider reads the transcript's end only for busy sessions and keeps
the start, so the verdict follows the clock while the file stands still."
git push origin main
```

---

### Task 6: The purple dashed ring

**Files:**
- Modify: `Symbiodock/Island/LayerAnimation.swift` (`SpinningArc`)
- Modify: `Symbiodock/Island/Agents/AgentStatusMark.swift`
- Modify: `Symbiodock/App/DebugRender.swift` (`StatusMarkGallery`)

**Interfaces:**
- Consumes: `AgentRowState.compacting`, `AgentPalette.compacting` (Task 2).
- Produces: `SpinningArc(color:lineWidth:period:sweep:dashCount:)`.

- [ ] **Step 1: Let `SpinningArc` draw dashes**

Add `var dashCount: Int? = nil` after `sweep` (doc: `/// Draws the arc as this many dashes with equal gaps; nil for a solid arc.`). Pass it through: `view.configure(color: NSColor(color), lineWidth: lineWidth, period: period, sweep: sweep, dashCount: dashCount)`. In `ArcView` add `private var dashCount: Int?`, extend `configure` with `dashCount: Int?` and treat a change like a change of `sweep`:

```swift
        func configure(color: NSColor, lineWidth: CGFloat, period: TimeInterval, sweep: Double, dashCount: Int?) {
            arc.strokeColor = color.cgColor
            arc.lineWidth = lineWidth
            if self.period != period || self.sweep != sweep || self.dashCount != dashCount {
                self.period = period
                self.sweep = sweep
                self.dashCount = dashCount
                needsLayout = true
            }
            startSpinning()
        }
```

In `layout()`, after `arc.path = path`:

```swift
            if let dashCount, dashCount > 0 {
                let piece = 2 * .pi * radius / CGFloat(2 * dashCount)
                arc.lineDashPattern = [NSNumber(value: Double(piece)), NSNumber(value: Double(piece))]
            } else {
                arc.lineDashPattern = nil
            }
```

- [ ] **Step 2: Give the mark its compacting look**

In `AgentStatusMark`:

```swift
    private static let compactPeriod: TimeInterval = 2.0
    private static let compactDashes = 8

    private var isCompacting: Bool { state == .compacting }

    /// Whether the ring turns: a working arc, or a compacting ring of dashes.
    private var turns: Bool { state == .working || isCompacting }

    private var period: TimeInterval { isCompacting ? Self.compactPeriod : Self.turnPeriod }

    /// A dash and its gap along the still compacting ring.
    private var dashLength: CGFloat {
        .pi * (size - Self.stroke) / CGFloat(2 * Self.compactDashes)
    }
```

Change `spins` to `private var spins: Bool { animates && turns }`. In `mark`, change the frozen turn to use `turns` and `period`:

```swift
        let turn = time.map { turns ? $0.truncatingRemainder(dividingBy: period) / period * 360 : 0 } ?? 0
```

Change the still circle's stroke style and the live arc:

```swift
            Circle()
                .trim(from: 0, to: state == .working ? 0.75 : 1)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: Self.stroke, lineCap: .round,
                        dash: isCompacting ? [dashLength, dashLength] : []))
                .rotationEffect(.degrees(turn - 90))
                .opacity(spins ? 0 : 1)
            if spins {
                SpinningArc(
                    color: color, lineWidth: Self.stroke, period: period,
                    sweep: isCompacting ? 1 : 0.75,
                    dashCount: isCompacting ? Self.compactDashes : nil)
                    .transition(.opacity)
            }
```

Update the type's doc comment first line to: `/// One glyph for a session's state, used wherever a state is shown. Working turns, compacting turns a purple ring of dashes, needs input knocks, finished draws a check; the rest stand still.`

- [ ] **Step 3: Add it to the gallery**

In `StatusMarkGallery.states`, after `("working", .working, 0.2)` add `("compacting", .compacting, 0.3),`, and widen the gallery: in `DebugRender.runIfRequested` change the `status-marks` size to `CGSize(width: 640, height: 150)`.

- [ ] **Step 4: Build and look**

Run the build command, then:
`SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`
Expected: `build/render/status-marks.png` shows a purple ring of eight dashes beside the working arc. Open it with the Read tool to check.

- [ ] **Step 5: Commit and push**

```bash
git add Symbiodock/Island/LayerAnimation.swift Symbiodock/Island/Agents/AgentStatusMark.swift Symbiodock/App/DebugRender.swift
git commit -m "feat(agents): turn a purple dashed ring while a session compacts

The owner asked for a purple dashed loop in place of the right ring until
the compaction ends."
git push origin main
```

---

### Task 7: The pet's wave runs down while compacting

**Files:**
- Modify: `Symbiodock/Island/Agents/AgentPetWave.swift`
- Modify: `Symbiodock/Island/Agents/AgentPet.swift`
- Modify: `Symbiodock/App/DebugRender.swift` (`PetGallery`)

**Interfaces:**
- Consumes: `AgentPetMotion.downBand`, `.downCrestRange`, `.downCrest(at:)` (Task 4).
- Produces: `AgentPetWave(tool:strength:side:direction:)`, `AgentPetWave.Direction { across, down }`.

- [ ] **Step 1: Give the wave a direction**

In `AgentPetWave` add:

```swift
    /// Which way the crest runs: across from left to right (working), or down from top to
    /// bottom (compacting).
    enum Direction: Equatable {
        case across, down
    }

    var direction: Direction = .across
```

and pass it: `view.configure(tool: tool, strength: strength, side: side, direction: direction)`. Add `let direction: Direction` to `WaveView.Spec`, a `direction` parameter to `configure`, and carry `current.direction` wherever a `Spec` is rebuilt (`viewDidMoveToWindow`, `viewDidChangeBackingProperties`). Add `private var band: CAGradientLayer?` next to `columns`.

- [ ] **Step 2: Build the lines through one helper, and the crest for `.down`**

Replace `build(_:)` with:

```swift
        private func build(_ spec: Spec) {
            guard let root = layer else { return }
            for layer in columns { layer.removeAllAnimations() }
            band?.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.sublayers = nil
            columns = []
            band = nil

            let art = AgentPetArt.art(for: spec.tool, strength: spec.strength)
            for index in art.lines.indices {
                let line = makeLine(index, art: art, spec: spec)
                // Waiting for the crest a line stands back; the wave brings it forward.
                line.opacity = Float(AgentPetMotion.waveRest)
                root.addSublayer(line)
                columns.append(line)
            }
            if spec.direction == .down {
                root.addSublayer(makeCrest(art: art, spec: spec))
            }
            CATransaction.commit()
        }

        /// One line of the pet: its ground and the stretches where the figure is. Layer
        /// coordinates run upward from the lower left.
        private func makeLine(_ index: Int, art: AgentPetArt.Art, spec: Spec) -> CALayer {
            let side = spec.side
            let bar = side * AgentPetFigure.barWidth
            let inset = side * AgentPetArt.groundInset
            // Room around the pet for a line at the crest, as in the drawn pet.
            let margin = side * AgentPetMotion.waveGrowth / 2
            let line = CALayer()
            line.frame = CGRect(
                x: margin + side * AgentPetFigure.pitch * CGFloat(index), y: margin, width: bar, height: side)
            line.contentsScale = spec.scale

            let ground = CALayer()
            ground.frame = CGRect(x: 0, y: inset, width: bar, height: side - 2 * inset)
            ground.cornerRadius = bar / 2
            ground.backgroundColor = NSColor(art.grounds[index]).cgColor
            line.addSublayer(ground)

            for stretch in art.lines[index] {
                // In the top-left coordinates the `Canvas` draws in.
                let nominalTop = side * stretch.top
                let nominalBottom = side * stretch.bottom
                let top = max(nominalTop, inset)
                let bottom = min(max(nominalBottom, nominalTop + bar), side - inset)
                guard bottom > top else { continue }
                let paint = CAGradientLayer()
                paint.frame = CGRect(x: 0, y: side - bottom, width: bar, height: bottom - top)
                paint.cornerRadius = bar / 2
                let colors = stretch.gradient.stops.map { NSColor($0.color).cgColor }
                if colors.count >= 2 {
                    paint.colors = colors
                    paint.locations = stretch.gradient.stops.map { NSNumber(value: Double($0.location)) }
                } else {
                    // A gradient layer needs two colours; one colour is a plain fill.
                    paint.backgroundColor = colors.first
                }
                // The colours run from the stretch's own ends, which the layer may overshoot.
                paint.startPoint = CGPoint(x: 0.5, y: 1 - (nominalTop - top) / (bottom - top))
                paint.endPoint = CGPoint(x: 0.5, y: 1 - (nominalBottom - top) / (bottom - top))
                paint.contentsScale = spec.scale
                line.addSublayer(paint)
            }
            return line
        }

        /// The downward crest: the same lines in full colour and a touch wider, seen only
        /// through a soft band that runs down the pet (`animateBand`).
        private func makeCrest(art: AgentPetArt.Art, spec: Spec) -> CALayer {
            let whole = spec.side * (1 + AgentPetMotion.waveGrowth)
            let crest = CALayer()
            crest.frame = CGRect(x: 0, y: 0, width: whole, height: whole)
            for index in art.lines.indices {
                let line = makeLine(index, art: art, spec: spec)
                line.transform = CATransform3DMakeScale(1 + AgentPetMotion.waveGrowth, 1, 1)
                crest.addSublayer(line)
            }
            let mask = CAGradientLayer()
            mask.bounds = CGRect(x: 0, y: 0, width: whole, height: spec.side * AgentPetMotion.downBand)
            mask.position = CGPoint(
                x: whole / 2, y: Self.bandY(AgentPetMotion.downCrestRange.lowerBound, spec: spec))
            // A raised cosine across the band, as the crest across has.
            let steps = 12
            mask.colors = (0...steps).map { step in
                let distance = abs(Double(step) / Double(steps) - 0.5)
                return NSColor.black.withAlphaComponent(0.5 * (1 + cos(2 * .pi * distance))).cgColor
            }
            mask.locations = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
            crest.mask = mask
            band = mask
            return crest
        }

        /// The band's centre in layer coordinates for a crest at `fraction` of the pet's
        /// height from its top.
        private static func bandY(_ fraction: Double, spec: Spec) -> CGFloat {
            let margin = spec.side * AgentPetMotion.waveGrowth / 2
            return margin + spec.side * CGFloat(1 - fraction)
        }
```

- [ ] **Step 3: Animate the band**

Replace `animate()` with:

```swift
        private func animate() {
            guard window != nil, let spec = built else { return }
            let begin = (columns.first?.convertTime(0, from: nil) ?? 0) + Self.phaseShift
            switch spec.direction {
            case .across:
                for (column, line) in columns.enumerated() {
                    let forward = (0...Self.samples).map { step -> Double in
                        let time = AgentPetMotion.wavePeriod * Double(step % Self.samples) / Double(Self.samples)
                        return AgentPetMotion.wave(column: column, at: time)
                    }
                    line.add(
                        animation("transform.scale", forward.map { 1 + AgentPetMotion.waveGrowth * $0 }, begin: begin),
                        forKey: "wave")
                    let rest = AgentPetMotion.waveRest
                    line.add(
                        animation("opacity", forward.map { rest + (1 - rest) * $0 }, begin: begin),
                        forKey: "waveDepth")
                }
            case .down:
                animateBand(spec: spec, begin: begin)
            }
        }

        /// Runs the band down the pet at the crest's even pace (`AgentPetMotion.downCrest`),
        /// then straight back above it to wait. The two keyframes at the same moment make the
        /// jump, so the band never sweeps back up across the pet.
        private func animateBand(spec: Spec, begin: CFTimeInterval) {
            guard let band else { return }
            let entry = Double(Self.bandY(AgentPetMotion.downCrestRange.lowerBound, spec: spec))
            let exit = Double(Self.bandY(AgentPetMotion.downCrestRange.upperBound, spec: spec))
            let end = NSNumber(value: AgentPetMotion.waveTravel / AgentPetMotion.wavePeriod)
            let run = CAKeyframeAnimation(keyPath: "position.y")
            run.values = [entry, exit, entry, entry]
            run.keyTimes = [0, end, end, 1]
            run.calculationMode = .linear
            run.duration = AgentPetMotion.wavePeriod
            run.repeatCount = .infinity
            run.beginTime = begin
            run.isRemovedOnCompletion = false
            band.add(run, forKey: "band")
        }
```

In `viewDidMoveToWindow`'s `window == nil` branch also call `band?.removeAnimation(forKey: "band")`; in `stop()` also `band?.removeAllAnimations()` and `band = nil`. Update the type's doc comment: add `With `direction: .down` (a compacting session) the lines stand back and a band runs down the pet instead, inside which they show in full and a touch wider.`

Note on `rebuildIfNeeded()`: it already calls `build`, sets `built`, then `animate()`; `animate()` now reads `built`, so keep that order.

- [ ] **Step 4: Use it in `AgentPet`**

```swift
    /// Whether the wave is playing: the pet is then made of layers, not drawn.
    private var waves: Bool {
        frozenAt == nil && (state == .working || state == .compacting) && !reduceMotion
    }
```

In `body`, pass the direction and draw a still compacting pet for renders:

```swift
            if waves {
                AgentPetWave(
                    tool: tool, strength: strength, side: size,
                    direction: state == .compacting ? .down : .across)
                    .frame(
                        width: size * (1 + AgentPetMotion.waveGrowth),
                        height: size * (1 + AgentPetMotion.waveGrowth))
                    .transition(.opacity)
            } else if state == .compacting, let frozenAt {
                downFigure(at: frozenAt)
                    .transition(.opacity)
            } else {
                figure(waveAt: state == .working ? frozenAt : nil)
                    .transition(.opacity)
            }
```

Give `figure` a `widened` parameter — signature `private func figure(waveAt time: TimeInterval?, widened: Bool = false) -> some View` — and change its scaling line to:

```swift
                line.scaleBy(x: scale * (widened ? 1 + AgentPetMotion.waveGrowth : 1), y: scale)
```

Add:

```swift
    /// A compacting pet at one moment of its downward wave, drawn still; for renders. The
    /// lines stand back, and inside the crest's band they show in full and a touch wider.
    private func downFigure(at time: TimeInterval) -> some View {
        let margin = size * AgentPetMotion.waveGrowth / 2
        return ZStack {
            figure(waveAt: nil).opacity(AgentPetMotion.waveRest)
            if let crest = AgentPetMotion.downCrest(at: time) {
                figure(waveAt: nil, widened: true)
                    .mask {
                        LinearGradient(
                            stops: (0...12).map { step in
                                let distance = abs(Double(step) / 12 - 0.5)
                                return Gradient.Stop(
                                    color: .black.opacity(0.5 * (1 + cos(2 * .pi * distance))),
                                    location: CGFloat(step) / 12)
                            },
                            startPoint: .top, endPoint: .bottom)
                            .frame(height: size * AgentPetMotion.downBand)
                            .position(x: size / 2 + margin, y: margin + size * crest)
                    }
            }
        }
    }
```

Update the type's doc comment: `... while the session works a wave runs across it from left to right, in depth ...; while it compacts the wave runs from top to bottom; otherwise it stands still.`

- [ ] **Step 5: Add it to the gallery**

In `PetGallery.body`, after the `working` row:

```swift
            HStack(spacing: 18) {
                caption("compacting").frame(width: 44)
                ForEach([0.3, 0.65, 1.0], id: \.self) { time in
                    AgentPet(tool: .claudeCode, state: .compacting, size: 48, frozenAt: time)
                    AgentPet(tool: .codex, state: .compacting, size: 48, frozenAt: time)
                }
            }
```

and change the `pets` render height in `runIfRequested` to `460`.

- [ ] **Step 6: Build and look**

Run the build, then the render command from Task 6. Expected: `build/render/pets.png` shows, in the compacting row, a brighter band high on the pet at 0.3 s, in the middle at 0.65 s and low at 1.0 s. Open it with the Read tool.

- [ ] **Step 7: Commit and push**

```bash
git add Symbiodock/Island/Agents/AgentPetWave.swift Symbiodock/Island/Agents/AgentPet.swift Symbiodock/App/DebugRender.swift
git commit -m "feat(agents): run the pet's wave from top to bottom while compacting

The owner asked for the working wave turned downward during a compaction;
the band runs in Core Animation like the wave across."
git push origin main
```

---

### Task 8: The dashed line around the island

**Files:**
- Create: `Symbiodock/Island/CompactingRim.swift`
- Modify: `Symbiodock/Island/IslandView.swift` (`resting`)
- Modify: `Symbiodock/Agents/DemoAgents.swift`
- Modify: `Symbiodock/App/DebugRender.swift` (`CollapsedGallery`)

**Interfaces:**
- Consumes: `IslandState.showsCompactingRim` (Task 3), `AgentPalette.compacting` (Task 2), `IslandCornerRadii`, `ScreenEdge`, `IslandLayout.dockedEdges(anchor:)`.
- Produces: `CompactingRim(radii:dockedEdges:frozenAt:)`.

- [ ] **Step 1: Write the view**

```swift
import AppKit
import SwiftUI
import SymbiodockCore

/// A purple dashed line that runs clockwise around the collapsed island while the session
/// the agents face speaks for compacts its conversation. It lies on the island's outline,
/// inside it, and leaves out the edges against the screen, like `RimLight`. Live, the
/// dashes move by Core Animation (`MarchingRim`); still (renders, Reduce Motion) SwiftUI
/// draws them once.
struct CompactingRim: View {
    let radii: IslandCornerRadii
    let dockedEdges: Set<ScreenEdge>
    /// Draws the dashes where they are this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let lineWidth: CGFloat = 1.5
    static let dash: CGFloat = 6
    static let gap: CGFloat = 5
    /// How fast the dashes run along the rim, in points a second.
    static let speed: CGFloat = 40

    /// The dash phase `time` seconds in. It falls, so the dashes run forward along the
    /// outline, which goes clockwise.
    static func phase(at time: TimeInterval) -> CGFloat {
        -(CGFloat(time) * speed).truncatingRemainder(dividingBy: dash + gap)
    }

    var body: some View {
        Group {
            if frozenAt == nil, !reduceMotion {
                MarchingRim(radii: radii, dockedEdges: dockedEdges)
            } else {
                UnevenRoundedRectangle(
                    topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
                    bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
                    style: .continuous)
                    .strokeBorder(
                        AgentPalette.compacting,
                        style: StrokeStyle(
                            lineWidth: Self.lineWidth, dash: [Self.dash, Self.gap],
                            dashPhase: Self.phase(at: frozenAt ?? 0)))
                    .mask { Rectangle().padding(edgeInsets) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Hides the line on the edges that touch the screen: a notch has no line there.
    private var edgeInsets: EdgeInsets {
        EdgeInsets(
            top: dockedEdges.contains(.top) ? 3 : 0,
            leading: dockedEdges.contains(.left) ? 3 : 0,
            bottom: dockedEdges.contains(.bottom) ? 3 : 0,
            trailing: dockedEdges.contains(.right) ? 3 : 0)
    }
}

/// The live dashed line: one shape layer whose dash phase Core Animation moves.
private struct MarchingRim: NSViewRepresentable {
    let radii: IslandCornerRadii
    let dockedEdges: Set<ScreenEdge>

    func makeNSView(context: Context) -> RimView { RimView() }

    func updateNSView(_ view: RimView, context: Context) {
        view.configure(radii: radii, dockedEdges: dockedEdges)
    }

    final class RimView: NSView {
        private let line = CAShapeLayer()
        private let cut = CALayer()
        private var radii: IslandCornerRadii?
        private var dockedEdges: Set<ScreenEdge> = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            line.fillColor = nil
            line.strokeColor = NSColor(AgentPalette.compacting).cgColor
            line.lineWidth = CompactingRim.lineWidth
            line.lineDashPattern = [
                NSNumber(value: Double(CompactingRim.dash)), NSNumber(value: Double(CompactingRim.gap)),
            ]
            cut.backgroundColor = NSColor.black.cgColor
            line.mask = cut
            layer?.addSublayer(line)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(radii: IslandCornerRadii, dockedEdges: Set<ScreenEdge>) {
            if self.radii != radii || self.dockedEdges != dockedEdges {
                self.radii = radii
                self.dockedEdges = dockedEdges
                needsLayout = true
            }
            startMarching()
        }

        override func layout() {
            super.layout()
            guard let radii else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            line.frame = bounds
            cut.frame = Self.uncut(bounds, docked: dockedEdges)
            let inset = CompactingRim.lineWidth / 2
            line.path = Self.outline(in: bounds.insetBy(dx: inset, dy: inset), radii: radii)
            CATransaction.commit()
            startMarching()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                line.removeAnimation(forKey: "march")
            } else {
                startMarching()
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            line.contentsScale = window?.backingScaleFactor ?? 2
        }

        private func startMarching() {
            guard window != nil, line.animation(forKey: "march") == nil else { return }
            let period = CompactingRim.dash + CompactingRim.gap
            let march = CABasicAnimation(keyPath: "lineDashPhase")
            march.fromValue = 0
            march.toValue = -period
            march.duration = Double(period / CompactingRim.speed)
            march.repeatCount = .infinity
            march.timingFunction = CAMediaTimingFunction(name: .linear)
            march.isRemovedOnCompletion = false
            line.add(march, forKey: "march")
        }

        /// What the line may show: the bounds less 3 pt along each edge against the screen.
        /// Layer coordinates run upward, so the top edge is at `maxY`.
        private static func uncut(_ bounds: CGRect, docked: Set<ScreenEdge>) -> CGRect {
            var rect = bounds
            if docked.contains(.top) { rect.size.height -= 3 }
            if docked.contains(.bottom) { rect.origin.y += 3; rect.size.height -= 3 }
            if docked.contains(.left) { rect.origin.x += 3; rect.size.width -= 3 }
            if docked.contains(.right) { rect.size.width -= 3 }
            return rect
        }

        /// The island's outline, clockwise as seen on screen, starting at the left end of the
        /// top edge. Layer coordinates run upward: the top edge is at `maxY`.
        private static func outline(in rect: CGRect, radii: IslandCornerRadii) -> CGPath {
            let half = min(rect.width, rect.height) / 2
            let topLeading = min(radii.topLeading, half)
            let topTrailing = min(radii.topTrailing, half)
            let bottomTrailing = min(radii.bottomTrailing, half)
            let bottomLeading = min(radii.bottomLeading, half)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + topLeading, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - topTrailing, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.maxX - topTrailing, y: rect.maxY - topTrailing), radius: topTrailing,
                startAngle: .pi / 2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bottomTrailing))
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomTrailing, y: rect.minY + bottomTrailing),
                radius: bottomTrailing, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX + bottomLeading, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeading, y: rect.minY + bottomLeading),
                radius: bottomLeading, startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - topLeading))
            path.addArc(
                center: CGPoint(x: rect.minX + topLeading, y: rect.maxY - topLeading), radius: topLeading,
                startAngle: .pi, endAngle: .pi / 2, clockwise: true)
            path.closeSubpath()
            return path
        }
    }
}
```

- [ ] **Step 2: Show it on the island**

In `IslandView.resting`, after the `RimLight` overlay:

```swift
            .overlay {
                if state.showsCompactingRim {
                    CompactingRim(
                        radii: radii, dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor))
                }
            }
```

- [ ] **Step 3: A demo set and a render**

In `DemoAgents.apply`, add before `default:`:

```swift
        case "compacting":
            state.setAgentSessions([
                session("c", .claudeCode, "api-refactor", "backend", .compacting, minutes: 0.5), idle,
            ])
```

and add `compacting` to the list of sets in the type's doc comment.

In `CollapsedGallery`, add:

```swift
    private func compactingNotch(at time: TimeInterval) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: .notch, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: radii.bottomLeading, bottomTrailingRadius: radii.bottomTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { AgentNotchFace(row: row(.compacting), notchWidth: 200) }
            .overlay { CompactingRim(radii: radii, dockedEdges: [.top], frozenAt: time) }
            .frame(width: 272, height: 32)
            .clipShape(shape)
    }
```

and in `body`'s first `VStack`, after `notch(.working, .none, at: 0)`, add `compactingNotch(at: 0.1)`. Change the `collapsed-faces` render height to `540`.

- [ ] **Step 4: Build, render and run the demo**

Run the build and the render command. Expected: `build/render/collapsed-faces.png` shows a purple dashed line down the sides and along the bottom of the compacting notch face, none along the top. Then:

```bash
open --env SYMBIODOCK_DEMO_AGENTS=compacting build/Build/Products/Debug/Symbiodock.app
```

Take two screenshots a second apart (`screencapture -x -R` around the notch) and check the dashes moved; check CPU with `top -l 2 -pid $(pgrep -x Symbiodock) -stats cpu | tail -1` (expected `0.0`). Then `pkill -x Symbiodock`.

- [ ] **Step 5: Commit and push**

```bash
git add Symbiodock/Island/CompactingRim.swift Symbiodock/Island/IslandView.swift Symbiodock/Agents/DemoAgents.swift Symbiodock/App/DebugRender.swift
git commit -m "feat(island): run a purple dashed line around a compacting island

The owner asked for the dashed loop around the island as well as in the
ring; it leaves the rim light alone and never shows with it."
git push origin main
```

---

### Task 9: The finish seal

**Files:**
- Create: `Symbiodock/Island/Agents/FinishSeal.swift`
- Modify: `Symbiodock/Island/Agents/AgentStatusMark.swift` (make `CheckShape` internal)
- Modify: `Symbiodock/Island/Agents/AgentFaces.swift`
- Modify: `Symbiodock/Island/IslandView.swift`
- Modify: `Symbiodock/App/DebugRender.swift`

**Interfaces:**
- Consumes: `AgentSealTiming` (Task 4), `AgentRow.isSettled`, `IslandState.sealingID`, `IslandState.settleFinished(_:)` (Task 3).
- Produces: `FinishSeal(tool:size:frozenAt:)`.

- [ ] **Step 1: Share the check**

In `AgentStatusMark.swift` change `private struct CheckShape: Shape` to `struct CheckShape: Shape`.

- [ ] **Step 2: Write the seal**

```swift
import SwiftUI
import SymbiodockCore

/// A finished session's pet sealed the way Face ID confirms a face: corner brackets close in
/// on the pet, grow into a circle as the pet fades, and the circle turns mint around a
/// check (`AgentSealTiming`). It plays once, from when it appears; `IslandView` settles the
/// session when the seal is over. It redraws only while it moves, never at rest.
struct FinishSeal: View {
    let tool: AgentTool
    let size: CGFloat
    /// Draws the seal at this moment and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var drawn = false

    private static let stroke = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)

    var body: some View {
        Group {
            if let frozenAt {
                seal(AgentSealTiming.pose(at: frozenAt))
            } else if reduceMotion || drawn {
                seal(AgentSealTiming.finalPose)
            } else {
                TimelineView(.animation) { context in
                    seal(AgentSealTiming.pose(at: context.date.timeIntervalSince(start)))
                }
                .task {
                    // Once the check is drawn the seal holds still: stop redrawing.
                    try? await Task.sleep(for: .seconds(AgentSealTiming.checked))
                    drawn = true
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(tool.displayName), finished")
    }

    private func seal(_ pose: AgentSealTiming.Pose) -> some View {
        let side = size * CGFloat(pose.frameScale)
        return ZStack {
            AgentPet(tool: tool, state: .finished, size: size, frozenAt: 0)
                .scaleEffect(pose.petScale)
                .opacity(pose.petOpacity)
            ZStack {
                SealFrame(roundness: pose.roundness)
                    .stroke(.white.opacity(0.9 * (1 - pose.mint)), style: Self.stroke)
                SealFrame(roundness: pose.roundness)
                    .stroke(AgentPalette.mint.opacity(pose.mint), style: Self.stroke)
                CheckShape()
                    .trim(from: 0, to: pose.check)
                    .stroke(AgentPalette.mint, style: Self.stroke)
                    .frame(width: size * 0.42, height: size * 0.42)
            }
            .frame(width: side, height: side)
            .scaleEffect(pose.swell)
        }
    }
}

/// Face ID's frame: at roundness 0 four rounded corner brackets, which lengthen and round
/// until at 1 they are one circle.
private struct SealFrame: Shape {
    var roundness: Double

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let radius = side * CGFloat(0.22 + 0.28 * roundness)
        let outline = Self.outline(square, radius: min(radius, side / 2))
        // The share of each quarter of the outline that is drawn, centred on its corner.
        let share = 0.35 + 0.65 * roundness
        guard share < 0.999 else { return outline }
        var path = Path()
        for corner in 0..<4 {
            let centre = (Double(corner) + 0.5) / 4
            path.addPath(outline.trimmedPath(from: centre - share / 8, to: centre + share / 8))
        }
        return path
    }

    /// A rounded square from the middle of its top edge, clockwise; its corners' midpoints
    /// lie at 1/8, 3/8, 5/8 and 7/8 of its length.
    private static func outline(_ r: CGRect, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        path.addArc(
            center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(
            center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addArc(
            center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(
            center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
```

- [ ] **Step 3: Show it on the faces**

In `AgentFaces.swift` add:

```swift
/// The pet on a collapsed face. A finish that has not settled shows its seal in its place;
/// a new finish starts a new seal.
private struct AgentFacePet: View {
    let row: AgentRow

    var body: some View {
        if row.state == .finished, !row.isSettled {
            FinishSeal(tool: row.session.tool, size: 24)
                .id(row.id)
        } else {
            AgentPet(tool: row.session.tool, state: row.state, size: 24)
        }
    }
}
```

and replace `AgentPet(tool: row.session.tool, state: row.state, size: 24)` with `AgentFacePet(row: row)` in `AgentNotchFace`, `AgentFloatingFace` and `AgentSideFace` (keep the `.frame(maxWidth: .infinity)` in the notch face).

- [ ] **Step 4: Settle when the seal is over**

In `IslandView`, add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` after the stored properties, and append to `body` after `.ignoresSafeArea()`:

```swift
        // A finish on the collapsed island plays its seal, then lets go: the session settles
        // and the island closes. Opening the island or a question in the meantime cancels
        // the wait, and the seal plays again from the start the next time.
        .task(id: state.sealingID) {
            guard let id = state.sealingID else { return }
            let wait = reduceMotion ? AgentSealTiming.stillDuration : AgentSealTiming.duration
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            state.settleFinished(id)
        }
```

- [ ] **Step 5: Render the seal**

In `DebugRender.swift` add:

```swift
/// The finish seal at moments of its run.
private struct SealGallery: View {
    private static let times: [TimeInterval] = [0, 0.2, 0.45, 0.6, 0.75, 0.95, 1.5]

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Self.times, id: \.self) { time in
                VStack(spacing: 10) {
                    FinishSeal(tool: .claudeCode, size: 48, frozenAt: time)
                        .frame(width: 64, height: 64)
                    FinishSeal(tool: .codex, size: 24, frozenAt: time)
                    Text(String(format: "%.2f s", time))
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(16)
        .background(.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
```

and in `runIfRequested`, after the `pets` line: `write(SealGallery(), size: CGSize(width: 640, height: 150), named: "finish-seal", to: directory)`.

- [ ] **Step 6: Build, render and run the demo**

Run the build and the render command. Expected: `build/render/finish-seal.png` shows brackets wide around the pet at 0 s, close on it at 0.45 s, a ring with a faded pet at 0.75 s, a mint ring with a check at 1.5 s. Open it with the Read tool. Then:

```bash
open --env SYMBIODOCK_DEMO_AGENTS=finished build/Build/Products/Debug/Symbiodock.app
```

Screenshots at about 0.3 s, 1 s and 2.5 s after launch: the seal plays, then the wings close. Check CPU after it settles (`0.0`). `pkill -x Symbiodock`.

- [ ] **Step 7: Commit and push**

```bash
git add Symbiodock/Island/Agents/FinishSeal.swift Symbiodock/Island/Agents/AgentStatusMark.swift Symbiodock/Island/Agents/AgentFaces.swift Symbiodock/Island/IslandView.swift Symbiodock/App/DebugRender.swift
git commit -m "feat(agents): seal a finish like Face ID, then let the island close

The owner asked for an iPhone Face ID confirmation where the finished pet
stands, after which the island closes and the list keeps Done."
git push origin main
```

---

### Task 10: Record the work

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Decision log**

Add two rows to the `Karar kaydı` table, after `Pet parlaklığı`:

```markdown
| Bitiş efekti | Biten oturumun pet'i kapalı adada iPhone Face ID onayı gibi mühürlenir (köşe parantezleri kapanır, daireye döner, pet söner, nane yeşili ✓; 1,7 sn), sonra ada bırakır: kanatlar kapanır, kenar ışığı biter; listede `Done ✓` sekme açılana kadar kalır. Biten oturum, çalışan başka bir oturum olsa da efekt süresince yüzü alır. Müzik yüzünde sağdaki ✓ aynı süre görünür (2026-11-15) | Sahibi: "agentın işi bittiği zaman sol tarafta gözüken petin orada iphone face id onaylama efekti olsun ve öyle kapansın"; liste için B seçeneği ("öneriyi yap") (spec: `2026-11-15-finish-seal-and-compacting-design.md`) |
| Compact göstergesi | Claude Code `/compact` yaparken adanın kenarında mor (`#BF5AF2`) kesikli çizgi saat yönünde döner, sağdaki işaret mor kesikli halka olur ve döner, pet'in dalgası yukarıdan aşağı akar; compact bitince hepsi gider, bitiş sayılmaz. Hook yok: transcript'in sonundaki başlangıç izi (mesajı henüz yazılmamış `file-history-snapshot`; eski sürümlerde düz `/compact` kaydı) ve oturum dosyasındaki `busy` okunur. Otomatik compact ve Codex algılanmaz (2026-11-15) | Sahibi: "mor bir şekilde kesikli çizgilerle loop şeklinde compact bitene kadar dönsün", "hem adanın etrafında gezsin kesikli çizgi hem sağdaki halka yerine gelsin compact bitince de gitsin"; aynı Mac'teki Vibe Island bunu `PreCompact` hook'uyla yapıyor, bu proje hook kullanmıyor |
```

- [ ] **Step 2: Roadmap and status**

Under `Yol haritası`, after Faz 8, add:

```markdown
- [x] **Faz 9 — Face ID bitiş efekti ve compact göstergesi.** Kod tamam, elle kontrol bekliyor.
      Spec: `docs/superpowers/specs/2026-11-15-finish-seal-and-compacting-design.md`.
      Plan: `docs/superpowers/plans/2026-11-15-finish-seal-and-compacting.md` (elle kontrol listesi sonunda).
```

Under `Durum`, add a bullet with the final test count (from the last `swift test` run), what was checked through renders, screenshots and `top`, and what is left to the owner (the checklist below).

- [ ] **Step 3: Unverified assumptions**

Add to `Doğrulanmamış varsayımlar`:

```markdown
- Compact algılama (2026-11-15'te denendi, Claude Code 2.1.325): elle `/compact` başında
  transcript'e mesajı henüz yazılmamış bir `file-history-snapshot` düşüyor, komut kaydı compact
  bitince yazılıyor; oturum dosyası compact boyunca `busy` (18 sn'lik canlı denemede). İki
  örnekte görüldü. 2.1.303–2.1.318'de başta düz `/compact` kaydı var (8 örnek). `/model`
  penceresi açıkken transcript'e bir şey yazılmıyor, durum `waiting`/`dialog open`. Claude Code
  güncellenip iz değişirse oturum compact sırasında "çalışıyor" görünür; okuyucu yeni ize
  göre güncellenir.
- Claude Code `status: "shell"`: tur bitmiş, arka planda kabuk komutu sürüyor (bir oturumda iki
  kez görüldü). Boşta sayılıyor; başka anlamı çıkarsa buraya yazılır.
```

- [ ] **Step 4: Verify everything**

Run: `swift test --package-path Packages/SymbiodockCore` and the build command.
Expected: all tests pass, `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit and push**

```bash
git add CLAUDE.md
git commit -m "docs: record the finish seal and the compacting indicator"
git push origin main
```

---

## Manual checklist (for the owner)

1. Give a Claude Code session a short task. When it ends, the pet in the left wing is framed by corner brackets, they close into a circle, the pet fades, a mint check appears; about 1.7 s later the wings close.
2. Open the Agents tab: the session's row says `Done ✓`. Leave the tab: it goes.
3. While one session works, let another finish: the finished pet takes the face, plays the seal, and the face goes back to the working one.
4. With music playing and `Media` as the first tab, let a session finish: the right side shows the mint check for about 1.7 s, then the level bars return.
5. Hover the island during a seal: it opens. Leave without opening `Agents`: the seal plays again from the start.
6. In a session with some conversation, run `/compact`: within about 4 s a purple dashed line runs clockwise around the island, the right mark is a turning purple dashed ring, and the pet's wave runs from top to bottom.
7. When the compaction ends, all of it goes within a moment; no seal plays and no `Done ✓` appears.
8. Open the island during a compaction: the row shows `Compacting` with the purple ring; the dashed line belongs to the collapsed island only.
9. Dock the island at a corner or a side and compact: no line along the edges that touch the screen.
10. With Reduce Motion on: the seal shows still for 1 s; the dashed line and ring stand still.
11. While compacting, and after a seal, `top` shows Symbiodock at 0 %.
12. Finish a turn while a background command still runs (the session file says `shell`): the seal plays.
