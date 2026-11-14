# Agents Tab — Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The pure logic behind tabs and the Agents tab: the session model, the board that orders sessions and tracks attention, tab order and face selection, and the parsers for Claude Code, Codex and the process list.

**Architecture:** Everything here lives in `Packages/SymbiodockCore` and touches no file, process or UI API. Parsers take `Data` and return values; the app target (second plan, `2026-11-14-agents-tab-app.md`) does the reading. `IslandState` stays the single source of truth and gains the board and the tabs.

**Tech Stack:** Swift 6, Swift Testing (`import Testing`, `@Test`, `#expect`), Foundation only.

Spec: `docs/superpowers/specs/2026-11-14-agents-tab-design.md`.

## Global Constraints

- No third-party dependency. Foundation and CoreGraphics only in this package.
- Code, identifiers and comments in English. Interface text in English.
- Session titles, project paths, question text and process arguments are user content: never logged, never printed in a test failure message beyond the fixtures in this plan.
- A parser never throws and never crashes on bad input: it returns `nil` or leaves the record out.
- Fixtures are written by hand in the shapes below. Do not copy real files from `~/.claude` or `~/.codex` into the repository.
- Swift 6 strict concurrency: public value types are `Sendable`; `IslandState` stays `@MainActor`.
- Verify after every task: `swift test --package-path Packages/SymbiodockCore` passes (194 tests before this plan), and the app still builds:
  `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3` ends in `** BUILD SUCCEEDED **`.
- Commit after every task with a Conventional Commit (title ≤ 72 characters, imperative, body says why) and push to `main`. Never commit `Symbiodock.xcodeproj`.
- If code in this plan does not compile, fix it keeping behaviour and interfaces, and correct the plan in the same commit.

## File structure

| File (under `Packages/SymbiodockCore/Sources/SymbiodockCore/`) | Responsibility |
|---|---|
| `Agents/AgentSession.swift` | `AgentTool`, `AgentActivity`, `AgentSession` |
| `Agents/AgentSessionBoard.swift` | Ordering, finished marks, attention, lead |
| `Agents/AgentLabels.swift` | Row label and summary text |
| `IslandTab.swift` | `IslandTab`, `TabOrder`, `IslandFace`, `TabSelection` |
| `IslandState.swift` (modify) | Board, tab order, selected tab, `showsWings` |
| `IslandLayout.swift` (modify) | `hasTrack:` → `showsWings:`, `dockedEdges(anchor:)` |
| `Agents/ClaudeSessionParser.swift` | Session file → record → session; transcript path |
| `Agents/ClaudeTranscriptPromptReader.swift` | Pending question in a transcript tail |
| `Agents/CodexRolloutParser.swift` | Thread meta, turn state, listing rule, session |
| `Agents/CodexSessionIndex.swift` | Thread titles |
| `Agents/AgentProcess.swift` | `ProcessSnapshot`, `AgentProcessMatcher`, `ProcessTree`, `AgentScanContext`, `AgentSessionProvider`, `ProcessLevelProvider` |
| `Agents/AgentPetRelief.swift` | The pieces the pets are modelled from, and each tool's relief |
| `Agents/AgentPetFigure.swift` | Lighting a relief into brightness along 21 lines; how a pet moves |

Tests mirror these under `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/`.

---

### Task 1: Session model, board and labels

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSession.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSessionBoard.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentLabels.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentSessionBoardTests.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentLabelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `AgentTool` (`displayName`), `AgentActivity`, `AgentSession` (`init(id:tool:title:projectPath:activity:since:pid:hostAppPID:)`, `projectName`), `AgentAttention`, `AgentRowState`, `AgentRow`, `AgentSessionBoard` (`rows`, `update(_:)`, `markSeen()`, `attention`, `lead`, `hasFace`, `needsInputCount`, `workingCount`), `AgentLabels.duration(_:)`, `AgentLabels.status(_:since:now:)`, `AgentLabels.summary(needsInput:working:)`.

- [ ] **Step 1: Write the failing tests**

`AgentSessionBoardTests.swift`:

```swift
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
}
```

`AgentLabelsTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct AgentLabelsTests {
    @Test func durations() {
        #expect(AgentLabels.duration(-5) == "<1m")
        #expect(AgentLabels.duration(59) == "<1m")
        #expect(AgentLabels.duration(60) == "1m")
        #expect(AgentLabels.duration(59 * 60 + 59) == "59m")
        #expect(AgentLabels.duration(3600) == "1h 0m")
        #expect(AgentLabels.duration(3600 + 4 * 60) == "1h 4m")
        #expect(AgentLabels.duration(.infinity) == "<1m")
        #expect(AgentLabels.duration(1e300) == "87600h 0m")
    }

    @Test func statusLabels() {
        let since = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 125)
        #expect(AgentLabels.status(.working, since: since, now: now) == "Working 2m")
        #expect(AgentLabels.status(.needsInput(prompt: "x"), since: since, now: now) == "Needs input")
        #expect(AgentLabels.status(.finished, since: since, now: now) == "Done 2m")
        #expect(AgentLabels.status(.running, since: since, now: now) == "Running")
        #expect(AgentLabels.status(.idle, since: since, now: now) == "Idle 2m")
    }

    @Test func summaryLeavesOutEmptyGroups() {
        #expect(AgentLabels.summary(needsInput: 0, working: 0) == nil)
        #expect(AgentLabels.summary(needsInput: 1, working: 0) == "1 needs input")
        #expect(AgentLabels.summary(needsInput: 0, working: 2) == "2 working")
        #expect(AgentLabels.summary(needsInput: 1, working: 2) == "1 needs input · 2 working")
    }

    @Test func toolNames() {
        #expect(AgentTool.claudeCode.displayName == "Claude Code")
        #expect(AgentTool.copilotCLI.displayName == "Copilot CLI")
        #expect(AgentTool.allCases.count == 7)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: compile errors, `cannot find 'AgentSessionBoard' in scope`.

- [ ] **Step 3: Write the implementation**

`Agents/AgentSession.swift`:

```swift
import Foundation

/// The AI coding tools whose sessions the island can show.
public enum AgentTool: String, CaseIterable, Sendable {
    case claudeCode, codex, geminiCLI, cursorAgent, openCode, aider, copilotCLI

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .cursorAgent: "Cursor Agent"
        case .openCode: "OpenCode"
        case .aider: "Aider"
        case .copilotCLI: "Copilot CLI"
        }
    }
}

/// What a session is doing, as far as its tool lets us read it.
public enum AgentActivity: Equatable, Sendable {
    case working
    /// Waiting for the user. `prompt` is the question, when it could be read.
    case needsInput(prompt: String?)
    /// The turn is over and the session waits for the next request.
    case idle
    /// The tool is running; nothing more is known.
    case running
}

/// One session of an AI coding tool on this Mac.
public struct AgentSession: Identifiable, Equatable, Sendable {
    /// "<tool>:<native id>", unique across tools.
    public let id: String
    public let tool: AgentTool
    /// The session's name, or its project folder's name.
    public let title: String
    public let projectPath: String?
    public let activity: AgentActivity
    /// When `activity` began.
    public let since: Date
    /// The tool's own process, when known.
    public let pid: Int32?
    /// The regular app that hosts the session (a terminal, an editor), when one was found.
    public var hostAppPID: Int32?

    public init(
        id: String, tool: AgentTool, title: String, projectPath: String?,
        activity: AgentActivity, since: Date, pid: Int32?, hostAppPID: Int32? = nil
    ) {
        self.id = id
        self.tool = tool
        self.title = title
        self.projectPath = projectPath
        self.activity = activity
        self.since = since
        self.pid = pid
        self.hostAppPID = hostAppPID
    }

    /// The project folder's name, for display.
    public var projectName: String? {
        guard let projectPath else { return nil }
        let name = (projectPath as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
```

`Agents/AgentSessionBoard.swift`:

```swift
import Foundation

/// What the island should draw attention to.
public enum AgentAttention: Equatable, Sendable {
    case none
    /// A session finished and has not been looked at yet.
    case finished
    /// A session waits for the user.
    case needsInput
}

/// A session's state as the island shows it: its activity, plus "finished and not yet seen".
public enum AgentRowState: Equatable, Sendable {
    case needsInput(prompt: String?)
    case working
    case finished
    case running
    case idle

    /// Lower sorts first.
    var rank: Int {
        switch self {
        case .needsInput: 0
        case .working: 1
        case .finished: 2
        case .running: 3
        case .idle: 4
        }
    }
}

public struct AgentRow: Identifiable, Equatable, Sendable {
    public let session: AgentSession
    public let state: AgentRowState
    public var id: String { session.id }
}

/// Turns the providers' sessions into what the island shows: an ordered list, and what
/// deserves attention. It remembers which sessions it saw working, so it can tell a
/// session that has just finished from one that was idle all along.
public struct AgentSessionBoard: Equatable, Sendable {
    public private(set) var rows: [AgentRow] = []
    /// Sessions that were working or waiting on the last update.
    private var activeIDs: Set<String> = []
    /// Sessions seen going from active to idle and not looked at since.
    private var finishedIDs: Set<String> = []

    public init() {}

    /// Replaces the list. Of sessions sharing an id, the first is kept.
    public mutating func update(_ sessions: [AgentSession]) {
        var seen = Set<String>()
        var active = Set<String>()
        var unique: [AgentSession] = []
        for session in sessions where seen.insert(session.id).inserted {
            unique.append(session)
            switch session.activity {
            case .working, .needsInput:
                active.insert(session.id)
                finishedIDs.remove(session.id)
            case .idle:
                if activeIDs.contains(session.id) { finishedIDs.insert(session.id) }
            case .running:
                finishedIDs.remove(session.id)
            }
        }
        finishedIDs.formIntersection(seen)
        activeIDs = active
        rebuild(from: unique)
    }

    /// Forgets every finished mark: the user has looked.
    public mutating func markSeen() {
        guard !finishedIDs.isEmpty else { return }
        finishedIDs.removeAll()
        rebuild(from: rows.map(\.session))
    }

    public var attention: AgentAttention {
        var result = AgentAttention.none
        for row in rows {
            switch row.state {
            case .needsInput: return .needsInput
            case .finished: result = .finished
            case .working, .running, .idle: break
            }
        }
        return result
    }

    /// The session the collapsed island speaks for, if any deserves it.
    public var lead: AgentRow? {
        guard let first = rows.first else { return nil }
        switch first.state {
        case .needsInput, .working, .finished: return first
        case .running, .idle: return nil
        }
    }

    /// The session behind `attention`: the first that needs input, else the first that has
    /// finished. It can lie behind a working row, which `lead` would show instead.
    public var attentionRow: AgentRow? {
        rows.first { if case .needsInput = $0.state { true } else { false } }
            ?? rows.first { $0.state == .finished }
    }

    /// Whether the collapsed island has something to show for the agents.
    public var hasFace: Bool { lead != nil }

    public var needsInputCount: Int {
        rows.count { if case .needsInput = $0.state { true } else { false } }
    }

    public var workingCount: Int { rows.count { $0.state == .working } }

    private mutating func rebuild(from sessions: [AgentSession]) {
        rows = sessions
            .map { AgentRow(session: $0, state: state(of: $0)) }
            .sorted { lhs, rhs in
                if lhs.state.rank != rhs.state.rank { return lhs.state.rank < rhs.state.rank }
                if lhs.session.since != rhs.session.since {
                    return lhs.session.since > rhs.session.since
                }
                return lhs.id < rhs.id
            }
    }

    private func state(of session: AgentSession) -> AgentRowState {
        switch session.activity {
        case .needsInput(let prompt): .needsInput(prompt: prompt)
        case .working: .working
        case .running: .running
        case .idle: finishedIDs.contains(session.id) ? .finished : .idle
        }
    }
}
```

`Agents/AgentLabels.swift`:

```swift
import Foundation

/// The words the Agents tab uses.
public enum AgentLabels {
    /// 30 → "<1m", 125 → "2m", 3840 → "1h 4m".
    public static func duration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 60 else { return "<1m" }
        // Clamp first: Int(_:) traps for a huge finite value (ten years of minutes is plenty).
        let minutes = Int(min(interval / 60, 5_256_000))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    public static func status(_ state: AgentRowState, since: Date, now: Date) -> String {
        let elapsed = duration(now.timeIntervalSince(since))
        switch state {
        case .needsInput: return "Needs input"
        case .working: return "Working \(elapsed)"
        case .finished: return "Done \(elapsed)"
        case .running: return "Running"
        case .idle: return "Idle \(elapsed)"
        }
    }

    /// "1 needs input · 2 working"; nil when both counts are zero.
    public static func summary(needsInput: Int, working: Int) -> String? {
        var parts: [String] = []
        if needsInput > 0 { parts.append("\(needsInput) needs input") }
        if working > 0 { parts.append("\(working) working") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: `Test run with 210 tests in 19 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): model agent sessions and order them on a board"
git push origin main
```

---

### Task 2: Tabs, faces and island state

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandTab.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandLayout.swift`
- Modify (rename only): every caller of `hasTrack:` in `Packages/SymbiodockCore/Tests/` and `Symbiodock/`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandTabTests.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandStateTests.swift` (add)
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandLayoutTests.swift` (add)

**Interfaces:**
- Consumes: `AgentSession`, `AgentSessionBoard`, `AgentAttention` (Task 1).
- Produces:
  - `IslandTab` (`.agents`, `.media`), `TabOrder.default`, `TabOrder.repaired(_ raw: [String]?) -> [IslandTab]`, `TabOrder.moving(_:toFrontOf:) -> [IslandTab]`, `TabOrder.encode(_:) -> [String]`.
  - `IslandFace` (`.none`, `.media`, `.agents`), `TabSelection.face(order:mediaHasFace:agentsHasFace:) -> IslandFace`, `TabSelection.tabToOpen(order:attention:mediaHasContent:agentsHasContent:) -> IslandTab`.
  - `IslandState`: `board`, `tabOrder`, `selectedTab`, `mediaWings`, computed `showsWings` and `face`, `setAgentSessions(_:)`, `setTabOrder(_:)`, `selectTab(_:)`.
  - `IslandLayout`: every `hasTrack:` parameter is renamed `showsWings:`; `IslandLayout.dockedEdges(anchor:) -> Set<ScreenEdge>`.

- [ ] **Step 1: Rename the parameter everywhere**

The parameter means "the collapsed island at the notch is widened by its wings", which is no longer only about a track.

```bash
grep -rl 'hasTrack' Packages Symbiodock | xargs sed -i '' 's/hasTrack/showsWings/g'
swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1
```

Expected: `Test run with 210 tests in 19 suites passed`. The loop variables in `IslandLayoutTests` are renamed with it, which is fine.

- [ ] **Step 2: Write the failing tests**

`IslandTabTests.swift`:

```swift
import Testing
@testable import SymbiodockCore

struct IslandTabTests {
    @Test func defaultOrderPutsAgentsFirst() {
        #expect(TabOrder.default == [.agents, .media])
    }

    @Test func repairKeepsAValidOrder() {
        #expect(TabOrder.repaired(["media", "agents"]) == [.media, .agents])
    }

    @Test func repairFillsWhatIsMissing() {
        #expect(TabOrder.repaired(nil) == [.agents, .media])
        #expect(TabOrder.repaired([]) == [.agents, .media])
        #expect(TabOrder.repaired(["media"]) == [.media, .agents])
    }

    @Test func repairDropsUnknownAndRepeatedValues() {
        #expect(TabOrder.repaired(["weather", "media", "media", "agents"]) == [.media, .agents])
    }

    @Test func movingToTheFrontKeepsTheRest() {
        #expect(TabOrder.moving(.media, toFrontOf: [.agents, .media]) == [.media, .agents])
        #expect(TabOrder.moving(.agents, toFrontOf: [.agents, .media]) == [.agents, .media])
    }

    @Test func encodingRoundTrips() {
        #expect(TabOrder.repaired(TabOrder.encode([.media, .agents])) == [.media, .agents])
    }

    @Test func theFaceIsTheFirstTabThatHasOne() {
        let agentsFirst: [IslandTab] = [.agents, .media]
        let mediaFirst: [IslandTab] = [.media, .agents]
        #expect(TabSelection.face(order: agentsFirst, mediaHasFace: true, agentsHasFace: true) == .agents)
        #expect(TabSelection.face(order: mediaFirst, mediaHasFace: true, agentsHasFace: true) == .media)
        #expect(TabSelection.face(order: agentsFirst, mediaHasFace: true, agentsHasFace: false) == .media)
        #expect(TabSelection.face(order: mediaFirst, mediaHasFace: false, agentsHasFace: true) == .agents)
        #expect(TabSelection.face(order: agentsFirst, mediaHasFace: false, agentsHasFace: false) == .none)
    }

    @Test func attentionOpensTheAgentsTab() {
        for attention in [AgentAttention.needsInput, .finished] {
            #expect(
                TabSelection.tabToOpen(
                    order: [.media, .agents], attention: attention,
                    mediaHasContent: true, agentsHasContent: true) == .agents)
        }
    }

    @Test func otherwiseTheFirstTabWithContentOpens() {
        let mediaFirst: [IslandTab] = [.media, .agents]
        let agentsFirst: [IslandTab] = [.agents, .media]
        #expect(
            TabSelection.tabToOpen(
                order: mediaFirst, attention: .none,
                mediaHasContent: true, agentsHasContent: true) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: agentsFirst, attention: .none,
                mediaHasContent: true, agentsHasContent: false) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: mediaFirst, attention: .none,
                mediaHasContent: false, agentsHasContent: false) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: agentsFirst, attention: .none,
                mediaHasContent: false, agentsHasContent: false) == .agents)
    }
}
```

Append to `IslandStateTests.swift`, inside `struct IslandStateTests`:

```swift
    private func agent(_ id: String, _ activity: AgentActivity) -> AgentSession {
        AgentSession(
            id: id, tool: .claudeCode, title: id, projectPath: nil, activity: activity,
            since: Date(timeIntervalSince1970: 0), pid: nil)
    }

    @Test func aWorkingAgentWidensTheIsland() {
        let state = IslandState()
        #expect(!state.showsWings)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.showsWings)
        #expect(state.face == .agents)
        state.setAgentSessions([])
        #expect(!state.showsWings)
        #expect(state.face == .none)
    }

    @Test func theFaceFollowsTheTabOrder() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        #expect(state.face == .agents)
        state.setTabOrder([.media, .agents])
        #expect(state.face == .media)
        #expect(state.tabOrder == [.media, .agents])
    }

    @Test func hoverOpensTheFirstTabWithContent() {
        let state = IslandState()
        state.setTabOrder([.agents, .media])
        state.setNowPlaying(track(playing: true))
        state.setHovering(true)
        #expect(state.selectedTab == .media)
    }

    @Test func hoverOpensAgentsWhenOneNeedsInput() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        state.setHovering(true)
        #expect(state.selectedTab == .agents)
    }

    @Test func aClickChangesTheTabAndNewSessionsDoNot() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setHovering(true)
        #expect(state.selectedTab == .media)
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        #expect(state.selectedTab == .media)
        state.selectTab(.agents)
        #expect(state.selectedTab == .agents)
    }

    @Test func leavingTheAgentsTabClearsFinishedMarks() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.board.attention == .finished)

        state.setHovering(true)
        #expect(state.selectedTab == .agents)
        // Still marked while it is being looked at.
        #expect(state.board.attention == .finished)

        state.setHovering(false)
        #expect(state.board.attention == .none)
        #expect(!state.showsWings)
    }

    @Test func switchingAwayFromAgentsAlsoClearsFinishedMarks() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(true)
        state.selectTab(.media)
        #expect(state.board.attention == .none)
    }

    @Test func collapsingFromTheMediaTabKeepsFinishedMarks() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setHovering(true)
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(false)
        #expect(state.board.attention == .finished)
    }

    @Test func aDamagedTabOrderIsRepaired() {
        let state = IslandState()
        state.setTabOrder([.media])
        #expect(state.tabOrder == [.media, .agents])
    }
```

Add `import Foundation` at the top of `IslandStateTests.swift` if it is not there.

Append to `IslandLayoutTests.swift`, inside its test struct:

```swift
    @Test func dockedEdgesAreTheOnesTheIslandTouches() {
        #expect(IslandLayout.dockedEdges(anchor: .notch) == [.top])
        #expect(IslandLayout.dockedEdges(anchor: .edge(.left, fraction: 0.5)) == [.left])
        #expect(IslandLayout.dockedEdges(anchor: .edge(.bottom, fraction: 0.2)) == [.bottom])
        #expect(IslandLayout.dockedEdges(anchor: .corner(.topRight)) == [.top, .right])
        #expect(IslandLayout.dockedEdges(anchor: .corner(.bottomLeft)) == [.bottom, .left])
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: compile errors, `cannot find 'TabOrder' in scope`.

- [ ] **Step 4: Write the implementation**

`IslandTab.swift`:

```swift
import Foundation

/// The pages of the expanded island.
public enum IslandTab: String, CaseIterable, Sendable {
    case agents
    case media
}

/// The order of the tabs, as the user chose it. Stored as raw values.
public enum TabOrder {
    public static let `default`: [IslandTab] = [.agents, .media]

    /// Makes any stored list hold every tab exactly once: unknown and repeated values are
    /// dropped, missing tabs are appended in default order.
    public static func repaired(_ raw: [String]?) -> [IslandTab] {
        var order: [IslandTab] = []
        for value in raw ?? [] {
            if let tab = IslandTab(rawValue: value), !order.contains(tab) { order.append(tab) }
        }
        for tab in `default` where !order.contains(tab) { order.append(tab) }
        return order
    }

    public static func moving(_ tab: IslandTab, toFrontOf order: [IslandTab]) -> [IslandTab] {
        repaired(([tab] + order.filter { $0 != tab }).map(\.rawValue))
    }

    public static func encode(_ order: [IslandTab]) -> [String] {
        order.map(\.rawValue)
    }
}

/// What the collapsed island shows.
public enum IslandFace: Equatable, Sendable {
    case none
    case media
    case agents
}

public enum TabSelection {
    /// The first tab in order that has a face; `.none` if neither has.
    public static func face(
        order: [IslandTab], mediaHasFace: Bool, agentsHasFace: Bool
    ) -> IslandFace {
        for tab in order {
            switch tab {
            case .media where mediaHasFace: return .media
            case .agents where agentsHasFace: return .agents
            default: continue
            }
        }
        return .none
    }

    /// The tab the island opens on. Attention wins; then the first tab with something to
    /// show; then simply the first tab.
    public static func tabToOpen(
        order: [IslandTab], attention: AgentAttention,
        mediaHasContent: Bool, agentsHasContent: Bool
    ) -> IslandTab {
        if attention != .none { return .agents }
        for tab in order {
            switch tab {
            case .media where mediaHasContent: return .media
            case .agents where agentsHasContent: return .agents
            default: continue
            }
        }
        return order.first ?? TabOrder.default[0]
    }
}
```

In `IslandState.swift`:

1. Replace the `showsWings` stored property and its doc comment with:

```swift
    /// Whether the media face is shown collapsed (artwork and level bars).
    /// True while something plays, and for a grace period after it pauses, so a
    /// paused player does not occupy the menu bar all day.
    public private(set) var mediaWings = false

    /// The agent sessions, ordered, with what deserves attention.
    public private(set) var board = AgentSessionBoard()
    /// The tabs in the order the user chose.
    public private(set) var tabOrder: [IslandTab] = TabOrder.default
    /// The tab the expanded island shows.
    public private(set) var selectedTab: IslandTab = TabOrder.default[0]

    /// Whether the collapsed island at the notch is widened by its wings.
    public var showsWings: Bool { mediaWings || board.hasFace }

    /// What the collapsed island shows.
    public var face: IslandFace {
        TabSelection.face(
            order: tabOrder, mediaHasFace: mediaWings, agentsHasFace: board.hasFace)
    }
```

2. In `setNowPlaying(_:)` and `pausedGraceElapsed()` replace every assignment to `showsWings` with an assignment to `mediaWings`.

3. Replace `setHovering(_:)` with:

```swift
    /// Called after the hover delay has elapsed, not on every pointer move.
    /// Ignored unless the island is collapsed or expanded, so a late timer cannot cancel a drag.
    public func setHovering(_ hovering: Bool) {
        guard phase == .collapsed || phase == .expanded else { return }
        if hovering, phase == .collapsed {
            selectedTab = TabSelection.tabToOpen(
                order: tabOrder, attention: board.attention,
                mediaHasContent: nowPlaying != nil, agentsHasContent: !board.rows.isEmpty)
        }
        if !hovering, phase == .expanded { leaveSelectedTab() }
        phase = hovering ? .expanded : .collapsed
    }
```

4. In `beginDrag(at:from:)`, right after the `guard`, add:

```swift
        if phase == .expanded { leaveSelectedTab() }
```

5. Add at the end of the class:

```swift
    public func setAgentSessions(_ sessions: [AgentSession]) {
        var next = board
        next.update(sessions)
        // Assign only on change: every assignment redraws the island.
        if next != board { board = next }
    }

    /// Applies a tab order, repaired if it is damaged. A collapsed island will open on it.
    public func setTabOrder(_ order: [IslandTab]) {
        tabOrder = TabOrder.repaired(TabOrder.encode(order))
    }

    /// A click on a tab.
    public func selectTab(_ tab: IslandTab) {
        guard tab != selectedTab else { return }
        leaveSelectedTab()
        selectedTab = tab
    }

    /// Once the Agents tab has been looked at, what finished is no longer news.
    private func leaveSelectedTab() {
        guard selectedTab == .agents else { return }
        var next = board
        next.markSeen()
        if next != board { board = next }
    }
```

In `IslandLayout.swift`, add inside the second `extension IslandLayout` (next to `cornerRadii`):

```swift
    /// The screen edges the resting island lies against.
    public static func dockedEdges(anchor: IslandAnchor) -> Set<ScreenEdge> {
        switch anchor {
        case .notch: [.top]
        case .edge(let edge, _): [edge]
        case .corner(.topLeft): [.top, .left]
        case .corner(.topRight): [.top, .right]
        case .corner(.bottomLeft): [.bottom, .left]
        case .corner(.bottomRight): [.bottom, .right]
        }
    }
```

The app target reads `state.showsWings` in `IslandView.swift` and `OverlayController.swift`; both keep compiling because the name still exists as a computed property.

- [ ] **Step 5: Run the tests and build the app**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1`
Expected: `Test run with 229 tests in 20 suites passed`.

Run: `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Packages/SymbiodockCore Symbiodock
git commit -m "feat(core): add tabs, faces and the agent board to island state"
git push origin main
```

---

### Task 3: Claude Code parsers

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/ClaudeSessionParser.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/ClaudeTranscriptPromptReader.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/ClaudeSessionParserTests.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/ClaudeTranscriptPromptReaderTests.swift`

**Interfaces:**
- Consumes: `AgentSession`, `AgentActivity` (Task 1).
- Produces:
  - `ClaudeSessionRecord` (`pid: Int32`, `sessionID: String?`, `cwd: String?`, `name: String?`, `status: String?`, `waitingFor: String?`, `statusUpdatedAt: Date?`, `isSpare: Bool`).
  - `ClaudeSessionParser.maximumFileSize` (65 536), `.record(from: Data) -> ClaudeSessionRecord?`, `.session(from:prompt:fallbackSince:) -> AgentSession?`, `.transcriptRelativePath(cwd:sessionID:) -> String?`.
  - `ClaudeTranscriptPromptReader.tailSize` (262 144), `.pendingQuestion(inTail: Data) -> String?`.

Background, verified on this Mac on 2026-11-14 with Claude Code 2.1.325:

- `~/.claude/sessions/<pid>.json` is one JSON object. Fields used: `pid` (number), `sessionId`, `cwd`, `name`, `status` (`"busy"`, `"idle"`, `"waiting"`), `waitingFor` (string, present while waiting), `statusUpdatedAt` (milliseconds since 1970), `spare` (true for a pre-warmed process that is not a session yet).
- The transcript is `~/.claude/projects/<slug>/<sessionId>.jsonl`, where `<slug>` is `cwd` with every character that is not an ASCII letter or digit replaced by `-` (`/private/tmp/claude-501/-Users-x` → `-private-tmp-claude-501--Users-x`).
- A question is an `assistant` line whose `message.content` holds `{"type":"tool_use","id":…,"name":"AskUserQuestion","input":{"questions":[{"question":…}]}}`. Its answer is a `user` line whose `message.content` holds `{"type":"tool_result","tool_use_id":…}`.

- [ ] **Step 1: Write the failing tests**

`ClaudeSessionParserTests.swift`:

```swift
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
}
```

`ClaudeTranscriptPromptReaderTests.swift`:

```swift
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

    @Test func onlyItsOwnResultClosesAQuestion() {
        // A tool called in parallel with the question, or after it, is not an answer.
        #expect(read([ask(id: "t1", "Which tools first?"), otherTool]) == "Which tools first?")
        #expect(
            read([ask(id: "t1", "Which tools first?"), otherTool, result(for: "t9")])
                == "Which tools first?")
        #expect(read([ask(id: "t1", "Which tools first?"), otherTool, result(for: "t1")]) == nil)
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: compile errors, `cannot find 'ClaudeSessionParser' in scope`.

- [ ] **Step 3: Write the implementation**

`Agents/ClaudeSessionParser.swift`:

```swift
import Foundation

/// The fields Symbiodock reads from a Claude Code session file.
public struct ClaudeSessionRecord: Equatable, Sendable {
    public let pid: Int32
    public let sessionID: String?
    public let cwd: String?
    public let name: String?
    /// "busy", "idle", "waiting", or something newer.
    public let status: String?
    public let waitingFor: String?
    public let statusUpdatedAt: Date?
    /// A pre-warmed process that is not a session yet.
    public let isSpare: Bool
}

/// Reads `~/.claude/sessions/<pid>.json`, which Claude Code keeps for every running session.
public enum ClaudeSessionParser {
    public static let maximumFileSize = 64 * 1024

    public static func record(from data: Data) -> ClaudeSessionRecord? {
        guard data.count <= maximumFileSize,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = processID(object["pid"])
        else { return nil }
        let milliseconds = number(object["statusUpdatedAt"])
        return ClaudeSessionRecord(
            pid: pid,
            sessionID: object["sessionId"] as? String,
            cwd: object["cwd"] as? String,
            name: object["name"] as? String,
            status: object["status"] as? String,
            waitingFor: object["waitingFor"] as? String,
            statusUpdatedAt: milliseconds.flatMap { value in
                value > 0 && value < maximumMilliseconds ? Date(timeIntervalSince1970: value / 1000) : nil
            },
            isSpare: (object["spare"] as? Bool) == true)
    }

    /// About year 5138; anything larger is not a time.
    private static let maximumMilliseconds = 1e14

    /// A JSON number as a Double; a boolean is not a number here.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// A positive whole number that fits `Int32`; nil for anything else, so a huge value
    /// is rejected instead of wrapping around to a valid-looking pid.
    private static func processID(_ value: Any?) -> Int32? {
        guard let double = number(value), double >= 1, double <= Double(Int32.max),
              double == double.rounded()
        else { return nil }
        return Int32(double)
    }

    /// The session a record stands for; nil for a spare process.
    /// - Parameter prompt: the open question, if one was read from the transcript.
    /// - Parameter fallbackSince: used when the file does not say when the status began.
    public static func session(
        from record: ClaudeSessionRecord, prompt: String?, fallbackSince: Date
    ) -> AgentSession? {
        guard !record.isSpare else { return nil }
        let activity: AgentActivity =
            switch record.status {
            case "busy": .working
            case "idle": .idle
            case "waiting": .needsInput(prompt: prompt)
            default: .running
            }
        let name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = record.cwd.map { ($0 as NSString).lastPathComponent }
        let title = [name, folder].compactMap { $0 }.first { !$0.isEmpty && $0 != "/" }
        return AgentSession(
            id: "\(AgentTool.claudeCode.rawValue):\(record.pid)",
            tool: .claudeCode,
            title: title ?? AgentTool.claudeCode.displayName,
            projectPath: record.cwd,
            activity: activity,
            since: record.statusUpdatedAt ?? fallbackSince,
            pid: record.pid)
    }

    /// Where the session's transcript lies below `~/.claude`. Claude Code names the folder
    /// after the working directory, with everything but ASCII letters and digits as "-".
    /// Nil if either part is empty or the id could leave the folder.
    public static func transcriptRelativePath(cwd: String, sessionID: String) -> String? {
        guard !cwd.isEmpty, !sessionID.isEmpty,
              sessionID.unicodeScalars.allSatisfy({ isLetterOrDigit($0) || $0 == "-" })
        else { return nil }
        let slug = String(
            String.UnicodeScalarView(cwd.unicodeScalars.map { isLetterOrDigit($0) ? $0 : "-" }))
        return "projects/\(slug)/\(sessionID).jsonl"
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9": true
        default: false
        }
    }
}
```

`Agents/ClaudeTranscriptPromptReader.swift`:

```swift
import Foundation

/// Finds the question a Claude Code session is waiting on, in the end of its transcript.
public enum ClaudeTranscriptPromptReader {
    /// How much of the transcript's end is worth reading.
    public static let tailSize = 256 * 1024
    private static let maximumLength = 300
    private static let toolUseMarker = Data("\"tool_use\"".utf8)
    private static let toolResultMarker = Data("\"tool_result\"".utf8)

    /// The text of the last `AskUserQuestion` that has neither a result nor a later tool
    /// call after it. Lines that are cut off or are not JSON are skipped.
    public static func pendingQuestion(inTail data: Data) -> String? {
        var pending: (id: String, question: String)?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            // Most lines are neither; do not parse them.
            guard line.range(of: toolUseMarker) != nil || line.range(of: toolResultMarker) != nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { continue }
            for item in content {
                switch item["type"] as? String {
                case "tool_use":
                    // Another tool called alongside or after the question does not answer it.
                    if let asked = question(in: item) { pending = asked }
                case "tool_result":
                    if let id = item["tool_use_id"] as? String, id == pending?.id { pending = nil }
                default:
                    break
                }
            }
        }
        return pending?.question
    }

    /// The question of an `AskUserQuestion` call; nil for any other tool call.
    private static func question(in toolUse: [String: Any]) -> (id: String, question: String)? {
        guard toolUse["name"] as? String == "AskUserQuestion",
              let id = toolUse["id"] as? String,
              let input = toolUse["input"] as? [String: Any],
              let questions = input["questions"] as? [[String: Any]],
              let text = questions.first?["question"] as? String
        else { return nil }
        let oneLine = text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !oneLine.isEmpty else { return nil }
        return (id, String(oneLine.prefix(maximumLength)))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1`
Expected: `Test run with 250 tests in 22 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): read Claude Code session files and open questions"
git push origin main
```

---

### Task 4: Codex parsers

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/CodexRolloutParser.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/CodexSessionIndex.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/CodexRolloutParserTests.swift`

**Interfaces:**
- Consumes: `AgentSession`, `AgentActivity` (Task 1).
- Produces:
  - `CodexThreadMeta` (`id: String`, `cwd: String?`, `isSubagent: Bool`, `originator: String?`).
  - `CodexTurnState` (`isWorking: Bool`, `since: Date`).
  - `CodexRolloutParser.headSize` (1 048 576), `.tailSize` (262 144), `.meta(fromHead: Data) -> CodexThreadMeta?`, `.turnState(inTail: Data) -> CodexTurnState?`, `.isListed(_ state: CodexTurnState, modified: Date, now: Date) -> Bool`, `.session(meta:state:title:pid:) -> AgentSession`.
  - `CodexSessionIndex.titles(from: Data) -> [String: String]`.

Background, verified on this Mac on 2026-11-14:

- A rollout file `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<id>.jsonl` holds one JSON object per line: `{"timestamp":"2026-11-14T18:45:26.561Z","type":…,"payload":{…}}`.
- The first line has `"type":"session_meta"` and is about 22 KB. Its payload has `id`, `cwd`, `originator` (`"Codex Desktop"`), and for a sub-agent thread a non-empty `parent_thread_id` and a `source` object with a `subagent` key. A root thread has neither.
- A turn starts with `{"type":"event_msg","payload":{"type":"task_started",…}}` and ends with `task_complete` or `turn_aborted`.
- `~/.codex/session_index.jsonl` holds `{"id":…,"thread_name":…,"updated_at":…}` per line; a thread can appear several times and the last line counts.

- [ ] **Step 1: Write the failing tests**

`CodexRolloutParserTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: compile errors, `cannot find 'CodexRolloutParser' in scope`.

- [ ] **Step 3: Write the implementation**

`Agents/CodexRolloutParser.swift`:

```swift
import Foundation

/// What a Codex rollout file says about its thread in its first line.
public struct CodexThreadMeta: Equatable, Sendable {
    public let id: String
    public let cwd: String?
    /// A thread spawned by another thread; it is not shown on its own.
    public let isSubagent: Bool
    /// "Codex Desktop", ...
    public let originator: String?

    public init(id: String, cwd: String?, isSubagent: Bool, originator: String?) {
        self.id = id
        self.cwd = cwd
        self.isSubagent = isSubagent
        self.originator = originator
    }
}

/// Whether a Codex thread is in the middle of a turn, and since when.
public struct CodexTurnState: Equatable, Sendable {
    public let isWorking: Bool
    public let since: Date

    public init(isWorking: Bool, since: Date) {
        self.isWorking = isWorking
        self.since = since
    }
}

/// Reads `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, one JSON object per line.
public enum CodexRolloutParser {
    /// The first line is about 22 KB; this leaves ample room, and the provider keeps the
    /// meta once found.
    public static let headSize = 1024 * 1024
    public static let tailSize = 256 * 1024
    /// An idle thread is listed this long after its file last changed.
    public static let idleListing: TimeInterval = 30 * 60
    /// A turn whose file has not changed for this long is taken for abandoned.
    public static let workingListing: TimeInterval = 2 * 60 * 60

    private static let turnEvents: Set<String> = ["task_started", "task_complete", "turn_aborted"]
    private static let turnMarkers = turnEvents.map { Data("\"\($0)\"".utf8) }

    /// The thread described by the file's first line; nil if it is not a `session_meta` line.
    public static func meta(fromHead data: Data) -> CodexThreadMeta? {
        guard let line = data.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = payload["id"] as? String, !id.isEmpty
        else { return nil }
        let parent = payload["parent_thread_id"] as? String
        let source = payload["source"] as? [String: Any]
        return CodexThreadMeta(
            id: id,
            cwd: payload["cwd"] as? String,
            isSubagent: !(parent ?? "").isEmpty || source?["subagent"] != nil,
            originator: payload["originator"] as? String)
    }

    /// The last turn event in the end of the file; nil if there is none with a readable time.
    public static func turnState(inTail data: Data) -> CodexTurnState? {
        var state: CodexTurnState?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            // Most lines are model output; parse only the ones that can be turn events.
            guard turnMarkers.contains(where: { line.range(of: $0) != nil }),
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String, turnEvents.contains(type),
                  let stamp = object["timestamp"] as? String, let date = timestamp(stamp)
            else { continue }
            state = CodexTurnState(isWorking: type == "task_started", since: date)
        }
        return state
    }

    /// Whether a thread in this state, whose file last changed at `modified`, is still shown.
    public static func isListed(_ state: CodexTurnState, modified: Date, now: Date) -> Bool {
        now.timeIntervalSince(modified) <= (state.isWorking ? workingListing : idleListing)
    }

    public static func session(
        meta: CodexThreadMeta, state: CodexTurnState, title: String?, pid: Int32?
    ) -> AgentSession {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = meta.cwd.map { ($0 as NSString).lastPathComponent }
        let shown = [name, folder].compactMap { $0 }.first { !$0.isEmpty && $0 != "/" }
        return AgentSession(
            id: "\(AgentTool.codex.rawValue):\(meta.id)",
            tool: .codex,
            title: shown ?? AgentTool.codex.displayName,
            projectPath: meta.cwd,
            activity: state.isWorking ? .working : .idle,
            since: state.since,
            pid: pid)
    }

    /// "2026-11-14T18:45:26.561Z", with or without the fraction.
    static func timestamp(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
```

`Agents/CodexSessionIndex.swift`:

```swift
import Foundation

/// Reads `~/.codex/session_index.jsonl`: the names Codex gave its threads.
public enum CodexSessionIndex {
    /// Thread id → name. A thread listed more than once keeps its last name.
    public static func titles(from data: Data) -> [String: String] {
        var titles: [String: String] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? String, !id.isEmpty,
                  let name = object["thread_name"] as? String, !name.isEmpty
            else { continue }
            titles[id] = name
        }
        return titles
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1`
Expected: `Test run with 260 tests in 23 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): read Codex rollouts and thread names"
git push origin main
```

---

### Task 5: Processes and the provider interface

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentProcess.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentProcessTests.swift`

**Interfaces:**
- Consumes: `AgentSession`, `AgentTool` (Task 1).
- Produces:
  - `ProcessSnapshot` (`pid`, `parentPID`, `executablePath`, `arguments`, `workingDirectory`, `startTime`, `terminal: Int32?`; `arguments` and `workingDirectory` are `var`).
  - `AgentProcessMatcher.isInterpreter(_ executablePath: String) -> Bool`, `.tool(for: ProcessSnapshot) -> AgentTool?`, `.sessions(for: AgentTool, in: [ProcessSnapshot]) -> [AgentSession]`.
  - `ProcessTree.ancestors(of: Int32, in: [ProcessSnapshot]) -> [Int32]`.
  - `AgentScanContext` (`now: Date`, `processes: [ProcessSnapshot]`).
  - `protocol AgentSessionProvider: Sendable { var tool: AgentTool { get }; func sessions(in context: AgentScanContext) async -> [AgentSession] }`.
  - `ProcessLevelProvider(tool:)`.

`AgentProcessMatcher.tool(for:)` recognises Codex and the five tools that are detected at process level. It never returns `.claudeCode`: Claude Code is found through its session files, and its executable is named after its version.

- [ ] **Step 1: Write the failing tests**

`AgentProcessTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct AgentProcessTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    private func process(
        _ pid: Int32, parent: Int32 = 1, _ path: String, _ arguments: [String] = [],
        cwd: String? = nil, terminal: Int32? = 16_777_220, startOffset: TimeInterval = 0
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid, parentPID: parent, executablePath: path, arguments: arguments,
            workingDirectory: cwd, startTime: start.addingTimeInterval(startOffset),
            terminal: terminal)
    }

    @Test func nativeExecutablesAreMatchedByName() {
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/gemini")) == .geminiCLI)
        #expect(AgentProcessMatcher.tool(for: process(1, "/Users/me/.local/bin/cursor-agent")) == .cursorAgent)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/opencode")) == .openCode)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/aider")) == .aider)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/copilot")) == .copilotCLI)
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
                == .codex)
    }

    @Test func scriptsRunByAnInterpreterAreMatchedByTheirPath() {
        let node = "/opt/homebrew/bin/node"
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, node, ["node", "/opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js"]))
                == .geminiCLI)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node", "/opt/homebrew/bin/gemini"])) == .geminiCLI)
        // `-m` after the script is the tool's own option, not Python's module switch.
        #expect(
            AgentProcessMatcher.tool(for: process(1, node, ["node", "/opt/homebrew/bin/gemini", "-m", "some-model"]))
                == .geminiCLI)
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, node, ["node", "--no-warnings", "/usr/local/lib/node_modules/@github/copilot/index.js"]))
                == .copilotCLI)
        #expect(
            AgentProcessMatcher.tool(for: process(1, node, ["node", "/Users/me/.npm/opencode-ai/bin/opencode.js"]))
                == .openCode)
        #expect(
            AgentProcessMatcher.tool(for: process(1, node, ["node", "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"]))
                == .codex)
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, node, ["node", "/Users/me/.local/share/cursor-agent/versions/2026.01.02/index.js"]))
                == .cursorAgent)
        #expect(
            AgentProcessMatcher.tool(for: process(1, "/usr/bin/python3", ["python3", "/Users/me/.local/bin/aider"]))
                == .aider)
        #expect(
            AgentProcessMatcher.tool(for: process(1, "/usr/bin/python3.12", ["python3.12", "-m", "aider", "--model", "x"]))
                == .aider)
    }

    @Test func nearMissesAreNotMatched() {
        let node = "/opt/homebrew/bin/node"
        #expect(AgentProcessMatcher.tool(for: process(1, "/usr/bin/vim", ["vim", "/Users/me/aider/notes.md"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node", "/Users/me/copilot/server.js"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node", "server.js", "/opt/homebrew/bin/gemini"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node"])) == nil)
        // A package whose name merely begins like a tool's is another package.
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, node, ["node", "/usr/lib/node_modules/@github/copilot-language-server/dist/main.js"]))
                == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node", "/Users/me/opencode-ai-notes/build.js"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, "/usr/bin/python3", ["python3", "-m", "http.server"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/gemini-helper")) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, "/bin/zsh", ["zsh", "-c", "gemini"])) == nil)
        #expect(
            AgentProcessMatcher.tool(for: process(1, "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex-code-mode-host"))
                == nil)
    }

    @Test func interpreters() {
        #expect(AgentProcessMatcher.isInterpreter("/opt/homebrew/bin/node"))
        #expect(AgentProcessMatcher.isInterpreter("/usr/bin/python3"))
        #expect(AgentProcessMatcher.isInterpreter("/opt/homebrew/Cellar/python@3.12/bin/Python"))
        #expect(AgentProcessMatcher.isInterpreter("/Users/me/.bun/bin/bun"))
        #expect(!AgentProcessMatcher.isInterpreter("/bin/zsh"))
        #expect(!AgentProcessMatcher.isInterpreter("/opt/homebrew/bin/gemini"))
    }

    @Test func oneRowPerToolAndTerminal() {
        let sessions = AgentProcessMatcher.sessions(
            for: .geminiCLI,
            in: [
                process(10, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Alpha", terminal: 1, startOffset: 5),
                process(11, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Alpha", terminal: 1, startOffset: 9),
                process(12, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Beta", terminal: 2),
                process(13, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Gamma", terminal: nil),
                process(14, "/opt/homebrew/bin/aider", cwd: "/Users/me/Projects/Delta", terminal: 3),
            ])
        #expect(sessions.map(\.id) == ["geminiCLI:tty1", "geminiCLI:tty2"])
        #expect(sessions.map(\.title) == ["Alpha", "Beta"])
        #expect(sessions.map(\.pid) == [10, 12])
        #expect(sessions.allSatisfy { $0.activity == .running && $0.tool == .geminiCLI })
        #expect(sessions[0].since == start.addingTimeInterval(5))
        #expect(sessions[0].projectPath == "/Users/me/Projects/Alpha")
    }

    @Test func aProcessWithoutAFolderIsNamedAfterItsTool() {
        let sessions = AgentProcessMatcher.sessions(
            for: .aider, in: [process(1, "/opt/homebrew/bin/aider", cwd: nil, terminal: 4)])
        #expect(sessions.map(\.title) == ["Aider"])
    }

    @Test func ancestorsWalkUpToTheTop() {
        let processes = [
            process(100, parent: 50, "/opt/homebrew/bin/gemini"),
            process(50, parent: 20, "/bin/zsh"),
            process(20, parent: 1, "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
        ]
        #expect(ProcessTree.ancestors(of: 100, in: processes) == [50, 20])
        #expect(ProcessTree.ancestors(of: 20, in: processes) == [])
        #expect(ProcessTree.ancestors(of: 999, in: processes) == [])
    }

    @Test func ancestorsSurviveALoop() {
        let processes = [
            process(100, parent: 50, "/bin/a"),
            process(50, parent: 100, "/bin/b"),
        ]
        #expect(ProcessTree.ancestors(of: 100, in: processes) == [50])
    }

    @Test func theProcessLevelProviderListsItsOwnTool() async {
        let context = AgentScanContext(
            now: start,
            processes: [
                process(1, "/opt/homebrew/bin/opencode", cwd: "/Users/me/Projects/Alpha", terminal: 1),
                process(2, "/opt/homebrew/bin/aider", cwd: "/Users/me/Projects/Beta", terminal: 2),
            ])
        let provider = ProcessLevelProvider(tool: .openCode)
        #expect(provider.tool == .openCode)
        #expect(await provider.sessions(in: context).map(\.id) == ["openCode:tty1"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: compile errors, `cannot find 'ProcessSnapshot' in scope`.

- [ ] **Step 3: Write the implementation**

`Agents/AgentProcess.swift`:

```swift
import Foundation

/// One running process, as much of it as session detection needs.
public struct ProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let executablePath: String
    /// `argv`, read only for interpreter processes; empty otherwise.
    public var arguments: [String]
    /// Read only for processes that belong to a known tool.
    public var workingDirectory: String?
    public let startTime: Date
    /// The controlling terminal's device number; nil for a process without one.
    public let terminal: Int32?

    public init(
        pid: Int32, parentPID: Int32, executablePath: String, arguments: [String] = [],
        workingDirectory: String? = nil, startTime: Date, terminal: Int32?
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.startTime = startTime
        self.terminal = terminal
    }
}

/// Tells which AI coding tool a process belongs to, from its executable and arguments.
public enum AgentProcessMatcher {
    /// Executable or script names, without extension.
    private static let names: [String: AgentTool] = [
        "gemini": .geminiCLI,
        "cursor-agent": .cursorAgent,
        "opencode": .openCode,
        "aider": .aider,
        "copilot": .copilotCLI,
        "codex": .codex,
    ]
    /// Package folders that identify a tool wherever its entry script is called.
    private static let packages: [(marker: String, tool: AgentTool)] = [
        ("/@google/gemini-cli/", .geminiCLI),
        ("/@github/copilot/", .copilotCLI),
        ("/@openai/codex/", .codex),
        ("/opencode-ai/", .openCode),
        // Cursor's agent runs as `node …/cursor-agent/versions/<version>/index.js`.
        ("/cursor-agent/", .cursorAgent),
    ]
    private static let scriptExtensions: Set<String> = ["js", "mjs", "cjs", "py"]

    /// Whether the executable runs a script, so that the tool is named in its arguments.
    public static func isInterpreter(_ executablePath: String) -> Bool {
        let name = (executablePath as NSString).lastPathComponent.lowercased()
        return name == "node" || name == "bun" || name == "deno" || name.hasPrefix("python")
    }

    public static func tool(for process: ProcessSnapshot) -> AgentTool? {
        let name = (process.executablePath as NSString).lastPathComponent.lowercased()
        if let tool = names[name] { return tool }
        guard isInterpreter(process.executablePath) else { return nil }

        let arguments = Array(process.arguments.dropFirst())
        // The script is the first argument that is not an option. Python can name a module
        // instead (`python -m aider`); for other interpreters `-m` is the script's own flag.
        var script: String?
        for (index, argument) in arguments.enumerated() {
            if argument == "-m", name.hasPrefix("python") {
                guard arguments.indices.contains(index + 1) else { return nil }
                return names[arguments[index + 1].lowercased()] == .aider ? .aider : nil
            }
            if !argument.hasPrefix("-") {
                script = argument
                break
            }
        }
        guard let script else { return nil }
        if let package = packages.first(where: { script.contains($0.marker) }) { return package.tool }
        let file = (script as NSString).lastPathComponent
        let stem = scriptExtensions.contains((file as NSString).pathExtension.lowercased())
            ? (file as NSString).deletingPathExtension : file
        return names[stem.lowercased()]
    }

    /// Process-level sessions of one tool: one per terminal, from its oldest process.
    /// Processes without a terminal (helpers, editor extensions) are not sessions.
    public static func sessions(
        for tool: AgentTool, in processes: [ProcessSnapshot]
    ) -> [AgentSession] {
        var oldest: [Int32: ProcessSnapshot] = [:]
        for process in processes {
            guard let terminal = process.terminal, self.tool(for: process) == tool else { continue }
            if let known = oldest[terminal], known.startTime <= process.startTime { continue }
            oldest[terminal] = process
        }
        return oldest.keys.sorted().compactMap { terminal in
            guard let process = oldest[terminal] else { return nil }
            let folder = process.workingDirectory.map { ($0 as NSString).lastPathComponent }
            let title = folder.flatMap { $0.isEmpty || $0 == "/" ? nil : $0 }
            return AgentSession(
                id: "\(tool.rawValue):tty\(terminal)",
                tool: tool,
                title: title ?? tool.displayName,
                projectPath: process.workingDirectory,
                activity: .running,
                since: process.startTime,
                pid: process.pid)
        }
    }
}

public enum ProcessTree {
    /// The parent, grandparent and so on of a process, nearest first, stopping before
    /// `launchd`, at a process that is not in the list, or at a loop.
    public static func ancestors(of pid: Int32, in processes: [ProcessSnapshot]) -> [Int32] {
        let parents = Dictionary(
            processes.map { ($0.pid, $0.parentPID) }, uniquingKeysWith: { first, _ in first })
        var chain: [Int32] = []
        var visited: Set<Int32> = [pid]
        var current = pid
        while let parent = parents[current], parent > 1, parents[parent] != nil,
              visited.insert(parent).inserted {
            chain.append(parent)
            current = parent
        }
        return chain
    }
}

/// What every provider gets for one scan.
public struct AgentScanContext: Sendable {
    public let now: Date
    public let processes: [ProcessSnapshot]

    public init(now: Date, processes: [ProcessSnapshot]) {
        self.now = now
        self.processes = processes
    }
}

/// Finds the sessions of one tool. A provider returns what it is sure of: a record it
/// cannot read is left out, and it never throws.
public protocol AgentSessionProvider: Sendable {
    var tool: AgentTool { get }
    func sessions(in context: AgentScanContext) async -> [AgentSession]
}

/// Detection without any knowledge of the tool's files: a row says the tool is open.
public struct ProcessLevelProvider: AgentSessionProvider {
    public let tool: AgentTool

    public init(tool: AgentTool) {
        self.tool = tool
    }

    public func sessions(in context: AgentScanContext) async -> [AgentSession] {
        AgentProcessMatcher.sessions(for: tool, in: context.processes)
    }
}
```

Note for the `ancestorsWalkUpToTheTop` test: pid 20's parent is 1, which is not in the list, so the walk from 100 gives `[50, 20]` and stops.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1`
Expected: `Test run with 269 tests in 24 suites passed`.

- [ ] **Step 5: Build the app and commit**

Run: `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): match agent tools in the process list"
git push origin main
```

---

### Task 6: Pets

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentPetRelief.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentPetFigure.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentPetFigureTests.swift`

**Interfaces:**
- Consumes: `AgentTool` (Task 1).
- Produces:
  - `AgentPetFigure` (`lines: [[Double]]`, `stretches(ofLine:) -> [Stretch]`, `Stretch { top; bottom; shades }`), `AgentPetFigure.figure(for: AgentTool)`, `.lineCount` (21), `.samplesPerLine` (84), `.pitch`, `.barWidth`, `.groundStrength` (0.085), `.faintestShade` (0.3), `.glowShade` (1.8).
  - `AgentPetMotion.wave(column: Int, at: TimeInterval) -> Double`, `.waveGrowth` (0.10), `.waveRest` (0.82), `.wavePeriod` (2.4), `.waveTravel` (1.3), `.waveWidth` (5); the wave is in depth (0...1: how far forward a line is), not up and down.

A pet is the figure a tool is known by. The island draws it as a field of fine vertical lines in which the figure shows as the lines' brightness changing along their length. To get that brightness, each figure is modelled as a small relief (a height above the plane at every point of the unit square, built from domes, plates, tubes and holes) and lit from the upper left; what faces the light is bright, what turns away or stands back is dim. The figure records, for each of 21 lines, the brightness at 84 points along it, 0 where there is no figure.

History, so the next reader is not surprised: the pets were first seven thick bars, then a 17 × 17 drawing with three flat depths. The owner asked for finer lines, more detail and depth, and described what he was after: an advertisement in which the whole picture is vertical lines and faces appear in them through the lines' changing colour, with the volume of nose and cheeks readable. He then asked for stronger colour and a slightly gentler effect, which is why the shading keeps a high floor and a line is wider than its gap.

- [ ] **Step 1: Write the failing tests**

`AgentPetFigureTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct AgentPetFigureTests {
    /// Every shade of a figure that is not empty.
    private func ink(_ figure: AgentPetFigure) -> [Double] {
        figure.lines.flatMap { $0 }.filter { $0 > 0 }
    }

    @Test func everyToolHasAFigureOnEveryLine() {
        for tool in AgentTool.allCases {
            let figure = AgentPetFigure.figure(for: tool)
            #expect(figure.lines.count == AgentPetFigure.lineCount, "\(tool)")
            for line in figure.lines {
                #expect(line.count == AgentPetFigure.samplesPerLine, "\(tool)")
            }
        }
    }

    @Test func theLinesAndTheirGapsFillTheWidth() {
        let width = Double(AgentPetFigure.lineCount - 1) * AgentPetFigure.pitch + AgentPetFigure.barWidth
        #expect(abs(width - 1) < 1e-9)
    }

    @Test func aFigureAlwaysStandsOutFromTheGround() {
        #expect(AgentPetFigure.groundStrength < AgentPetFigure.faintestShade)
        for tool in AgentTool.allCases {
            let shades = ink(AgentPetFigure.figure(for: tool))
            let inRange = shades.allSatisfy {
                ($0 >= AgentPetFigure.faintestShade && $0 <= 1) || $0 == AgentPetFigure.glowShade
            }
            #expect(inRange, "\(tool)")
        }
    }

    @Test func aFigureFillsAFairPartOfItsSquare() {
        let all = Double(AgentPetFigure.lineCount * AgentPetFigure.samplesPerLine)
        for tool in AgentTool.allCases {
            let share = Double(ink(AgentPetFigure.figure(for: tool)).count) / all
            #expect(share > 0.1 && share < 0.8, "\(tool): \(share)")
        }
    }

    @Test func everyFigureHasLightAndShade() {
        for tool in AgentTool.allCases {
            // What the light does, leaving aside the parts that glow by themselves.
            let shades = ink(AgentPetFigure.figure(for: tool)).filter { $0 <= 1 }
            let range = (shades.max() ?? 0) - (shades.min() ?? 0)
            #expect(range >= 0.3, "\(tool): \(range)")
            #expect((shades.max() ?? 0) >= 0.9, "\(tool)")
        }
    }

    @Test func noTwoToolsShareAFigure() {
        let figures = AgentTool.allCases.map(AgentPetFigure.figure(for:))
        for (index, figure) in figures.enumerated() {
            #expect(!figures[(index + 1)...].contains(figure))
        }
    }

    @Test func aFigureIsTheSameEveryTime() {
        #expect(AgentPetFigure.figure(for: .codex) == AgentPetFigure.figure(for: .codex))
        #expect(
            AgentPetFigure.figure(for: .aider)
                == AgentPetFigure(model: AgentPetReliefs.model(for: .aider)))
    }

    @Test func aGlowingPartIsBrighterThanAnythingLit() {
        #expect(AgentPetFigure.glowShade > 1)
        // The prompt on the Codex cloud glows; a few lines carry it, not the whole figure.
        let codex = ink(AgentPetFigure.figure(for: .codex))
        let glowing = codex.filter { $0 == AgentPetFigure.glowShade }.count
        #expect(glowing > 0)
        #expect(Double(glowing) < 0.2 * Double(codex.count))
        // Glow shows only on the figure, never on the ground beside it.
        let model = AgentPetModel({ x, _ in x < 0.5 ? 0.3 : 0 }, glow: { _, _ in 1 })
        let figure = AgentPetFigure(model: model)
        let left = figure.lines[0].allSatisfy { $0 == AgentPetFigure.glowShade }
        let right = figure.lines[AgentPetFigure.lineCount - 1].allSatisfy { $0 == 0 }
        #expect(left)
        #expect(right)
    }

    @Test func aLineIsCutIntoItsStretches() {
        let figure = AgentPetFigure(lines: [[0, 0.5, 0.6, 0, 0.3], [0, 0, 0, 0, 0], []])
        #expect(
            figure.stretches(ofLine: 0) == [
                .init(top: 0.2, bottom: 0.6, shades: [0.5, 0.6]),
                .init(top: 0.8, bottom: 1, shades: [0.3]),
            ])
        #expect(figure.stretches(ofLine: 1).isEmpty)
        #expect(figure.stretches(ofLine: 2).isEmpty)
        #expect(figure.stretches(ofLine: 3).isEmpty)
        #expect(figure.stretches(ofLine: -1).isEmpty)
    }

    @Test func theStretchesOfAFigureCoverItsInk() {
        for tool in AgentTool.allCases {
            let figure = AgentPetFigure.figure(for: tool)
            var covered = 0
            for index in figure.lines.indices {
                for stretch in figure.stretches(ofLine: index) {
                    #expect(stretch.top >= 0 && stretch.bottom <= 1 && stretch.top < stretch.bottom, "\(tool)")
                    #expect(!stretch.shades.isEmpty, "\(tool)")
                    covered += stretch.shades.count
                }
            }
            #expect(covered == ink(figure).count, "\(tool)")
        }
    }

    @Test func aReliefThatMisbehavesGivesNoInk() {
        let figure = AgentPetFigure(relief: { x, _ in x < 0.5 ? .nan : .infinity })
        let empty = figure.lines.allSatisfy { line in line.allSatisfy { $0 == 0 } }
        #expect(empty)
    }

    private static let frame = 1.0 / 60.0
    private static let columns = 0..<AgentPetFigure.lineCount

    /// The moment in one period at which a line is forward the most, found by sampling.
    private func peak(ofColumn column: Int) -> (time: TimeInterval, lift: Double, count: Int) {
        let steps = 2400
        let values = (0..<steps).map {
            AgentPetMotion.wave(column: column, at: Double($0) * AgentPetMotion.wavePeriod / Double(steps))
        }
        let top = values.max() ?? 0
        let first = values.firstIndex(of: top) ?? 0
        // Count separate rises above 90 % of the height.
        var rises = 0
        for index in values.indices where values[index] > 0.9 {
            if index == 0 || values[index - 1] <= 0.9 { rises += 1 }
        }
        return (Double(first) * AgentPetMotion.wavePeriod / Double(steps), top, rises)
    }

    @Test func aLineIsNeverMoreThanFullyForward() {
        for step in 0..<1000 {
            let time = Double(step) * 0.0071
            for column in Self.columns {
                let lift = AgentPetMotion.wave(column: column, at: time)
                #expect(lift >= 0 && lift <= 1 + 1e-12)
            }
        }
        #expect(AgentPetMotion.waveGrowth > 0 && AgentPetMotion.waveGrowth <= 0.15)
        #expect(AgentPetMotion.waveRest >= 0.6 && AgentPetMotion.waveRest < 1)
    }

    @Test func everyLineRisesToTheFullHeightOncePerPeriod() {
        for column in Self.columns {
            let result = peak(ofColumn: column)
            #expect(abs(result.lift - 1) < 0.01, "\(column)")
            #expect(result.count == 1, "\(column)")
        }
    }

    @Test func theCrestTravelsFromLeftToRight() {
        let left = peak(ofColumn: 0).time
        let middle = peak(ofColumn: AgentPetFigure.lineCount / 2).time
        let right = peak(ofColumn: AgentPetFigure.lineCount - 1).time
        #expect(left < middle)
        #expect(middle < right)
        #expect(right <= AgentPetMotion.waveTravel)
    }

    @Test func thePetRestsOnceTheCrestHasLeft() {
        var time = AgentPetMotion.waveTravel
        while time < AgentPetMotion.wavePeriod {
            for column in Self.columns {
                #expect(AgentPetMotion.wave(column: column, at: time) == 0)
            }
            time += 0.01
        }
        // And the pet starts the period at rest, too.
        for column in Self.columns {
            #expect(AgentPetMotion.wave(column: column, at: 0) < 1e-9)
        }
    }

    @Test func theLiftChangesSmoothly() {
        // Between two frames at 60 a second no line may change by more than a quarter of its
        // travel.
        for step in 0..<1500 {
            let time = Double(step) * 0.0013 - 1
            for column in Self.columns {
                let change = abs(
                    AgentPetMotion.wave(column: column, at: time + Self.frame)
                        - AgentPetMotion.wave(column: column, at: time))
                #expect(change <= 0.25)
            }
        }
    }

    @Test func theWaveRepeatsEveryPeriodAndAlsoBeforeTheReferenceDate() {
        for step in 0..<200 {
            let time = Double(step) * 0.017
            for column in Self.columns {
                let now = AgentPetMotion.wave(column: column, at: time)
                #expect(abs(AgentPetMotion.wave(column: column, at: time + AgentPetMotion.wavePeriod) - now) < 1e-9)
                #expect(abs(AgentPetMotion.wave(column: column, at: time - 5 * AgentPetMotion.wavePeriod) - now) < 1e-9)
            }
        }
        #expect(AgentPetMotion.wave(column: 10, at: -AgentPetMotion.wavePeriod + 0.65) > 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: compile errors, `cannot find 'AgentPetFigure' in scope`.

- [ ] **Step 3: Write the implementation**

`Agents/AgentPetRelief.swift`:

```swift
import Foundation

/// A relief: how high a figure rises above the plane at each point of the unit square
/// (x to the right, y downward). 0 means there is nothing there.
typealias AgentPetRelief = @Sendable (_ x: Double, _ y: Double) -> Double

/// A pet as it is modelled: its relief, and the parts of it that give off light of their
/// own (a prompt on a screen) and are therefore brighter than anything the light falls on.
struct AgentPetModel: Sendable {
    let relief: AgentPetRelief
    var glow: AgentPetRelief?

    init(_ relief: @escaping AgentPetRelief, glow: AgentPetRelief? = nil) {
        self.relief = relief
        self.glow = glow
    }
}

/// The pieces the pets are modelled from, and the pets themselves. A pet is the figure its
/// tool is known by, shaped as a small relief so that light can fall on it.
enum AgentPetReliefs {
    // MARK: Pieces

    /// Half an ellipsoid lying on the plane.
    static func dome(
        _ centerX: Double, _ centerY: Double, _ radiusX: Double, _ radiusY: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let inside = 1 - pow((x - centerX) / radiusX, 2) - pow((y - centerY) / radiusY, 2)
            return inside > 0 ? height * sqrt(inside) : 0
        }
    }

    /// A plate with round corners and a rounded shoulder `bevel` wide.
    static func slab(
        _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
        radius: Double, bevel: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let offsetX = abs(x - (left + right) / 2) - ((right - left) / 2 - radius)
            let offsetY = abs(y - (top + bottom) / 2) - ((bottom - top) / 2 - radius)
            let outside = hypot(max(offsetX, 0), max(offsetY, 0)) + min(max(offsetX, offsetY), 0) - radius
            guard outside < 0 else { return 0 }
            let across = min(-outside / bevel, 1)
            // A quarter circle: steep at the edge, flat on top.
            return height * sqrt(1 - (1 - across) * (1 - across))
        }
    }

    /// Half a tube lying between two points.
    static func tube(
        _ fromX: Double, _ fromY: Double, _ toX: Double, _ toY: Double,
        radius: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let alongX = toX - fromX
            let alongY = toY - fromY
            let part = min(
                max(((x - fromX) * alongX + (y - fromY) * alongY) / (alongX * alongX + alongY * alongY), 0), 1)
            let distance = hypot(x - (fromX + part * alongX), y - (fromY + part * alongY))
            return distance < radius ? height * sqrt(1 - (distance / radius) * (distance / radius)) : 0
        }
    }

    /// A four-pointed star, faceted like a cut stone.
    static func star(
        _ centerX: Double, _ centerY: Double, _ radius: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let reach = pow(abs(x - centerX) / radius, 0.62) + pow(abs(y - centerY) / radius, 0.62)
            return reach < 1 ? height * (1 - reach) : 0
        }
    }

    /// The near corner of a cube: three faces falling away from the centre, inside a hexagon.
    static func cubeCorner(
        _ centerX: Double, _ centerY: Double, _ radius: Double, _ height: Double
    ) -> AgentPetRelief {
        { x, y in
            let pointX = (x - centerX) / radius
            let pointY = (y - centerY) / radius
            let hexagon = max(
                abs(pointX) / 0.866, abs(pointX * 0.5 / 0.866 + pointY), abs(pointX * 0.5 / 0.866 - pointY))
            guard hexagon <= 1 else { return 0 }
            let fall = max(-pointY, -0.866 * pointX + 0.5 * pointY, 0.866 * pointX + 0.5 * pointY)
            return height * (1 - 0.6 * fall)
        }
    }

    /// A plain rectangle, for holes: 1 inside, 0 outside.
    static func box(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> AgentPetRelief {
        { x, y in x >= left && x <= right && y >= top && y <= bottom ? 1 : 0 }
    }

    /// Whichever piece is highest at each point.
    static func union(_ pieces: AgentPetRelief...) -> AgentPetRelief {
        { x, y in pieces.reduce(0) { max($0, $1(x, y)) } }
    }

    /// The base with nothing left wherever a hole is.
    static func cut(_ base: @escaping AgentPetRelief, _ holes: AgentPetRelief...) -> AgentPetRelief {
        { x, y in holes.contains { $0(x, y) > 0 } ? 0 : base(x, y) }
    }

    /// The base pressed down to `depth` wherever the hole is: glass, a screen.
    static func recess(
        _ base: @escaping AgentPetRelief, _ hole: @escaping AgentPetRelief, to depth: Double
    ) -> AgentPetRelief {
        { x, y in
            let height = base(x, y)
            return height > 0 && hole(x, y) > 0 ? min(height, depth) : height
        }
    }

    // MARK: Pets

    static func model(for tool: AgentTool) -> AgentPetModel {
        switch tool {
        case .claudeCode: AgentPetModel(claudeCode)
        case .codex: codex
        case .geminiCLI: AgentPetModel(geminiCLI)
        case .cursorAgent: AgentPetModel(cursorAgent)
        case .openCode: AgentPetModel(openCode)
        case .aider: AgentPetModel(aider)
        case .copilotCLI: AgentPetModel(copilotCLI)
        }
    }

    /// A plump creature standing on two small feet: one big round body with five soft
    /// bumps (on top, at the shoulders, at the hips), so its outline is a rounded star,
    /// and two small upright eyes, each one line wide.
    private static var claudeCode: AgentPetRelief {
        let body = dome(0.50, 0.48, 0.37, 0.33, 0.58)
        let bumps = union(
            dome(0.50, 0.19, 0.18, 0.15, 0.34),
            dome(0.21, 0.36, 0.17, 0.17, 0.34), dome(0.79, 0.36, 0.17, 0.17, 0.34),
            dome(0.27, 0.70, 0.18, 0.15, 0.34), dome(0.73, 0.70, 0.18, 0.15, 0.34))
        let feet = union(
            dome(0.30, 0.89, 0.10, 0.075, 0.26), dome(0.70, 0.89, 0.10, 0.075, 0.26))
        return cut(
            union(body, bumps, feet),
            box(0.38, 0.40, 0.43, 0.54), box(0.57, 0.40, 0.62, 0.54))
    }

    /// A plump cloud of round lobes with a prompt glowing on its front: ">" and "_".
    private static var codex: AgentPetModel {
        let body = union(
            dome(0.50, 0.51, 0.34, 0.31, 0.56),
            dome(0.33, 0.37, 0.21, 0.20, 0.44), dome(0.63, 0.33, 0.23, 0.22, 0.48),
            dome(0.18, 0.55, 0.17, 0.17, 0.38), dome(0.82, 0.53, 0.17, 0.18, 0.40),
            dome(0.34, 0.68, 0.22, 0.19, 0.44), dome(0.67, 0.68, 0.22, 0.19, 0.44))
        let prompt = union(
            tube(0.33, 0.46, 0.45, 0.55, radius: 0.034, 1),
            tube(0.45, 0.55, 0.33, 0.64, radius: 0.034, 1),
            tube(0.53, 0.64, 0.69, 0.64, radius: 0.034, 1))
        return AgentPetModel(body, glow: prompt)
    }

    /// A four-pointed star, and a small one far behind it.
    private static var geminiCLI: AgentPetRelief {
        union(star(0.46, 0.54, 0.46, 0.55), star(0.84, 0.16, 0.15, 0.24))
    }

    /// A cube seen from a corner; the light gives each of its three faces its own tone.
    private static var cursorAgent: AgentPetRelief {
        cubeCorner(0.5, 0.5, 0.47, 0.5)
    }

    /// A terminal window with a prompt on its screen, ">" and "_", and a second window
    /// behind it.
    private static var openCode: AgentPetRelief {
        let far = slab(0.28, 0.06, 0.98, 0.66, radius: 0.06, bevel: 0.05, 0.16)
        let near = slab(0.02, 0.24, 0.76, 0.92, radius: 0.06, bevel: 0.06, 0.44)
        let screen = box(0.10, 0.40, 0.68, 0.84)
        let prompt = union(
            tube(0.18, 0.50, 0.28, 0.60, radius: 0.03, 0.4),
            tube(0.28, 0.60, 0.18, 0.70, radius: 0.03, 0.4),
            tube(0.38, 0.72, 0.54, 0.72, radius: 0.03, 0.4))
        return union(far, recess(near, screen, to: 0.10), prompt)
    }

    /// The letter A made of three tubes: the left stroke nearest, the right one farthest.
    private static var aider: AgentPetRelief {
        union(
            tube(0.54, 0.10, 0.90, 0.90, radius: 0.085, 0.20),
            tube(0.30, 0.62, 0.72, 0.62, radius: 0.07, 0.32),
            tube(0.50, 0.10, 0.12, 0.90, radius: 0.095, 0.48))
    }

    /// A round helmeted head: two goggles with sunken glass, two eyes below them, an ear
    /// on each side.
    private static var copilotCLI: AgentPetRelief {
        let head = dome(0.5, 0.50, 0.44, 0.42, 0.52)
        let ears = union(dome(0.05, 0.52, 0.07, 0.13, 0.2), dome(0.95, 0.52, 0.07, 0.13, 0.2))
        let glass = union(
            slab(0.17, 0.30, 0.45, 0.55, radius: 0.09, bevel: 0.02, 1),
            slab(0.55, 0.30, 0.83, 0.55, radius: 0.09, bevel: 0.02, 1))
        return cut(
            union(ears, recess(head, glass, to: 0.07)),
            box(0.36, 0.66, 0.41, 0.78), box(0.59, 0.66, 0.64, 0.78))
    }
}
```

`Agents/AgentPetFigure.swift`:

```swift
import Foundation

/// A tool's pet as the island draws it: a field of fine vertical lines, where the figure
/// shows as the lines' brightness changing along their length. The figure is a small
/// relief lit from the upper left, so its forms read as volume: what faces the light is
/// bright, what turns away or stands back is dim. All measures are fractions of the
/// figure's side.
public struct AgentPetFigure: Equatable, Sendable {
    /// A stretch of one line where the figure is, with the brightness along it.
    public struct Stretch: Equatable, Sendable {
        /// 0 is the top of the figure, 1 its bottom.
        public let top: Double
        public let bottom: Double
        /// Brightness from `top` to `bottom`, evenly spaced, each above 0. Up to 1 it is
        /// how much of the tool's colour shows; above 1 the part glows, towards white.
        public let shades: [Double]
    }

    public static let lineCount = 21
    /// How finely the brightness along a line is recorded.
    public static let samplesPerLine = 4 * lineCount
    /// From one line's leading edge to the next: the lines and their gaps fill the width.
    public static let pitch = 1.0 / (Double(lineCount - 1) + barShare)
    /// A line is a little wider than the gap beside it, so the colour stays strong.
    public static let barWidth = barShare * pitch
    private static let barShare = 0.6
    /// How bright the lines are where there is no figure: the ground it stands out from.
    public static let groundStrength = 0.085
    /// The dimmest a part of a figure can be, so that it always stands out from the ground.
    public static let faintestShade = 0.36
    /// The brightness of a part that gives off light of its own: most of the way to white.
    public static let glowShade = 1.8

    /// Brightness along each line, left to right and top to bottom; 0 where the line shows
    /// only the ground, `glowShade` where the figure glows.
    public let lines: [[Double]]

    init(lines: [[Double]]) {
        self.lines = lines
    }

    /// The figure of a tool. Each is worked out once and kept.
    public static func figure(for tool: AgentTool) -> AgentPetFigure {
        figures[tool] ?? AgentPetFigure(model: AgentPetReliefs.model(for: tool))
    }

    private static let figures: [AgentTool: AgentPetFigure] = Dictionary(
        uniqueKeysWithValues: AgentTool.allCases.map {
            ($0, AgentPetFigure(model: AgentPetReliefs.model(for: $0)))
        })

    /// The stretches of one line where the figure is, top to bottom.
    public func stretches(ofLine index: Int) -> [Stretch] {
        guard lines.indices.contains(index) else { return [] }
        let line = lines[index]
        guard !line.isEmpty else { return [] }
        let count = Double(line.count)
        var stretches: [Stretch] = []
        var start: Int?
        for row in 0...line.count {
            let inked = row < line.count && line[row] > 0
            if inked, start == nil { start = row }
            guard !inked, let from = start else { continue }
            start = nil
            stretches.append(
                Stretch(top: Double(from) / count, bottom: Double(row) / count, shades: Array(line[from..<row])))
        }
        return stretches
    }
}

// MARK: Lighting

extension AgentPetFigure {
    /// Where the light comes from: upper left, towards the viewer.
    private static let light = (x: -0.52, y: -0.62, z: 0.59)
    /// A relief's outline is a cliff; a cliff this steep or steeper is lit as this steep.
    private static let steepestSlope = 2.2
    private static let step = 0.006

    /// Lights a relief and records what each line sees of it.
    init(relief: @escaping AgentPetRelief) {
        self.init(model: AgentPetModel(relief))
    }

    /// Lights a model and records what each line sees of it. Where the model glows, on
    /// the figure, the line is at `glowShade` whatever the light does.
    init(model: AgentPetModel) {
        let peak = Self.peak(of: model.relief)
        lines = (0..<Self.lineCount).map { column in
            let x = Double(column) * Self.pitch + Self.barWidth / 2
            return (0..<Self.samplesPerLine).map { row in
                let y = (Double(row) + 0.5) / Double(Self.samplesPerLine)
                let shade = Self.shade(of: model.relief, x: x, y: y, peak: peak)
                guard shade > 0, let glow = model.glow, glow(x, y) > 0 else { return shade }
                return Self.glowShade
            }
        }
    }

    /// The highest point of a relief.
    private static func peak(of relief: AgentPetRelief) -> Double {
        var highest = 0.0
        for column in 0..<60 {
            for row in 0..<60 {
                highest = max(highest, relief((Double(column) + 0.5) / 60, (Double(row) + 0.5) / 60))
            }
        }
        return max(highest, 0.001)
    }

    /// How bright the relief is at a point: 0 where there is nothing.
    private static func shade(of relief: AgentPetRelief, x: Double, y: Double, peak: Double) -> Double {
        let height = relief(x, y)
        guard height > 0, height.isFinite else { return 0 }
        let slopeX = clamp((relief(x + step, y) - relief(x - step, y)) / (2 * step))
        let slopeY = clamp((relief(x, y + step) - relief(x, y - step)) / (2 * step))
        let length = sqrt(slopeX * slopeX + slopeY * slopeY + 1)
        let facing = max(0, (-slopeX * light.x - slopeY * light.y + light.z) / length)
        // What stands farther back is dimmer. The shading is kept gentle: the figure should
        // read as a form, and still show its tool's colour at full strength where lit.
        let nearness = 0.68 + 0.32 * min(height / peak, 1)
        return min(max(pow((0.52 + 0.48 * facing) * nearness, 0.62), faintestShade), 1)
    }

    private static func clamp(_ slope: Double) -> Double {
        slope.isFinite ? min(max(slope, -steepestSlope), steepestSlope) : 0
    }
}

/// How a pet moves. Pure functions of time, so the views only draw.
public enum AgentPetMotion {
    /// How much larger a line is drawn at the crest of the wave, about its own centre: a
    /// touch thicker and longer, as if it came towards the viewer.
    public static let waveGrowth = 0.10
    /// How strongly a line shows while it waits for the crest; at the crest it shows in
    /// full. What is nearer is brighter, in the pet's own colours: nothing white is added.
    public static let waveRest = 0.82
    /// Seconds from the start of one crest to the start of the next.
    public static let wavePeriod: TimeInterval = 2.4
    /// Seconds a crest takes to cross the pet, from entering at the left to leaving at the
    /// right; the pet rests for the remainder of the period.
    public static let waveTravel: TimeInterval = 1.3
    /// How many lines wide a crest is: the width of the raised cosine.
    public static let waveWidth = 5.0

    /// How far forward line `column` (0 is the leftmost of `AgentPetFigure.lineCount`) is at
    /// `time`: 0 at rest, 1 at the crest. The wave travels in depth, not up and down. One
    /// crest runs from the left edge to the right edge, each line coming forward and going
    /// back smoothly as it passes; then the pet rests until the next crest.
    public static func wave(column: Int, at time: TimeInterval) -> Double {
        var beat = time.truncatingRemainder(dividingBy: wavePeriod)
        if beat < 0 { beat += wavePeriod }
        guard beat < waveTravel else { return 0 }
        // The crest enters half its width before the first line and leaves half its width
        // after the last, so every line is at rest when the crest starts and ends.
        let reach = Double(AgentPetFigure.lineCount - 1) + waveWidth
        let crest = -waveWidth / 2 + reach * beat / waveTravel
        let distance = abs(Double(column) - crest)
        guard distance < waveWidth / 2 else { return 0 }
        return 0.5 * (1 + cos(2 * .pi * distance / waveWidth))
    }
}
```

The figures are tuned by eye from renders (`SYMBIODOCK_RENDER_DIR`, app plan Task 1); any change must keep these tests passing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1`
Expected: every test passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): model each agent tool's pet as a lit relief"
git push origin main
```

---

## Spec coverage

| Spec section | Task |
|---|---|
| 4 Model, 4.1 board | 1 |
| 5 Tab order, which tab opens | 2 |
| 6.1 Claude Code session file and question text | 3 |
| 6.2 Codex rollout, titles, listing rule | 4 |
| 6.3 Process matching, one row per tool and terminal | 5 |
| 7.3 Faces, `showsWings` | 2 |
| 7.4 Labels and times | 1 |
| 7.5 Pets: figures and motion | 6 |
| 8 Parent walk for the hosting app | 5 |
| 9 Malformed input, unknown status, damaged tab order | 2, 3, 4 |
| 10 Core tests | 1–5 |

Deviations from the first version of the spec, written back into it together with this plan:

- The provider protocol takes an `AgentScanContext` instead of `now:`, so the process list is read once per scan and shared.
- `AgentSession` has `hostAppPID`, filled by the app, so a row knows whether it can be clicked without the view walking processes.
- Finished marks are cleared when the island leaves the Agents tab, not when it shows it, so the rows still say `Done` while they are looked at.
- A Codex turn whose file has not changed for two hours is no longer listed as working.

The file and process access, the views and the wiring are in `2026-11-14-agents-tab-app.md`.
