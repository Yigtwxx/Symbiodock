# Subagent Branches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a session's subagents as fork-like branches under its row, open the island at 600 × 150, show a waiting session in amber, and clear the question look within 0.3 s of the answer.

**Architecture:** Pure logic (subagent model, branch rules, file parsers, scan pacing, layout sizes) lives in `Packages/SymbiodockCore` and is tested with `swift test`. File access (subagent folders, rollouts, FSEvents) lives in `Symbiodock/Agents/`. Views live in `Symbiodock/Island/`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, CoreServices (FSEvents), Swift Testing, XcodeGen.

Spec: `docs/superpowers/specs/2026-11-15-subagent-branches-design.md`.

## Global Constraints

- Swift 6, macOS 14.0 minimum. No new third-party dependency.
- Read-only: nothing is written into `~/.claude` or `~/.codex`; no hooks.
- Subagent names, session titles, paths and questions are never logged, at any level.
- Interface text is English.
- No view redraws frame by frame at rest; the branches add no animation.
- Open island `600 × 150`; at a side edge `600 × 170`.
- Question color `#FFD60A` (255, 214, 10).
- At most three branch lines; with more subagents, two lines and `+N more`.
- Each task ends with: core tests green, Debug build green, commit, `git push origin main`.
  Conventional Commits, title ≤ 72 characters, body says why, ending with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01BW1DAFBgzicFoQakMEsPVS
  ```

Verification commands used below:

```bash
swift test --package-path Packages/SymbiodockCore
```

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
```

---

### Task 1: Open island 600 × 150

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandLayout.swift:5`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandLayoutTests.swift`
- Modify: `Symbiodock/App/DebugRender.swift` (`ExpandedPreview`, render sizes)

**Interfaces:**
- Produces: `IslandLayout.expandedSize == CGSize(width: 600, height: 150)`. The side-docked open size stays `max(expandedSize.height, sideCollapsedSize.height)` tall, so it becomes 600 × 170 with no code change.

- [ ] **Step 1: Update the layout tests to the new size**

In `IslandLayoutTests.swift` replace the expected frames:

```swift
    @Test func expandedIslandIsCenteredOnTheNotchAndHangsFromTheTop() {
        #expect(IslandLayout.frame(phase: .expanded, notch: notch, screenSize: screen, showsWings: false)
            == CGRect(x: 456, y: 0, width: 600, height: 150))
    }

    @Test func expandedIslandStaysInsideTheLeftEdge() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: leftNotch, screenSize: screen, showsWings: false)
            == CGRect(x: 0, y: 0, width: 600, height: 150))
    }

    @Test func expandedIslandStaysInsideTheRightEdge() {
        let rightNotch = CGRect(x: 1302, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: rightNotch, screenSize: screen, showsWings: false)
            == CGRect(x: 912, y: 0, width: 600, height: 150))
    }

    @Test func expandedIslandIsNeverNarrowerThanTheNotch() {
        let wideNotch = CGRect(x: 406, y: 0, width: 700, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: wideNotch, screenSize: screen, showsWings: false)
            == CGRect(x: 406, y: 0, width: 700, height: 150))
    }
```

In `hitRectIsTheFrameGrownByFourPoints`, the expanded expectation becomes:

```swift
        #expect(IslandLayout.hitRect(phase: .expanded, notch: notch, screenSize: screen, showsWings: false)
            == CGRect(x: 452, y: -4, width: 608, height: 158))
```

In `expandedIslandIgnoresTheWings`:

```swift
            == CGRect(x: 456, y: 0, width: 600, height: 150))
```

`expandingGrowsTowardTheInside` becomes:

```swift
    @Test func expandingGrowsTowardTheInside() {
        #expect(
            floating(.corner(.bottomRight), .expanded)
                == CGRect(x: 912, y: 762, width: 600, height: 150))
        #expect(
            floating(.edge(.bottom, fraction: 0.5), .expanded)
                == CGRect(x: 456, y: 762, width: 600, height: 150))
        #expect(
            floating(.edge(.right, fraction: 0), .expanded)
                == CGRect(x: 912, y: 32, width: 600, height: 170))
    }
```

(The wide-notch test moves to a 700 pt notch: a 620 pt notch is now narrower than the island and would no longer test the rule.)

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter IslandLayoutTests`
Expected: FAIL, frames with width 540 and height 134.

- [ ] **Step 3: Change the size**

`IslandLayout.swift:5`:

```swift
    public static let expandedSize = CGSize(width: 600, height: 150)
```

- [ ] **Step 4: Run all core tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: PASS. If any other test hard-codes 540 or 134 for the open island, update it to the frame the new size gives (`grep -rn "540\|134" Packages/SymbiodockCore/Tests` finds none today).

- [ ] **Step 5: Update the off-screen preview**

In `Symbiodock/App/DebugRender.swift`, `ExpandedPreview`:

```swift
/// The open island as it is at the notch: 600 × 150, with a 200 × 32 camera housing.
private struct ExpandedPreview: View {
    let state: IslandState

    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
        ExpandedIsland(
            state: state,
            metrics: ExpandedHeaderMetrics(height: 32, leading: 200, gap: 200, trailing: 200),
            onCommand: { _ in }, onOpenSession: { _ in })
            .frame(width: 600, height: 150)
            .background(.black, in: shape)
            .clipShape(shape)
    }
}
```

In `runIfRequested`, both `CGSize(width: 580, height: 180)` become `CGSize(width: 640, height: 190)`.

- [ ] **Step 6: Build, render, look**

Run the build command. Expected: `** BUILD SUCCEEDED **`.
Run: `SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`
Open `build/render/expanded-agents.png` and `build/render/expanded-media.png` with the Read tool: the island is wider and taller, rows and media still centred, nothing clipped.

- [ ] **Step 7: Commit and push**

```bash
git add Packages/SymbiodockCore Symbiodock/App/DebugRender.swift
git commit -m "feat(island): open the island at 600 x 150" -m "The owner found the open island too short; the extra height also makes room for subagent branches."
git push origin main
```

(Add the attribution lines from Global Constraints to every commit body.)

---

### Task 2: Amber for a waiting session

**Files:**
- Modify: `Symbiodock/Island/Agents/AgentPalette.swift:7-13`

**Interfaces:**
- Produces: `AgentPalette.alert` is amber. Its users (`RimLight`, `TabStrip`, `AgentStatusMark`, `AgentsContent`) need no change.

- [ ] **Step 1: Change the color and its comments**

```swift
    /// A session waits for the user. #FFD60A, amber: red read as a failure.
    static let alert = Color(red: 1.0, green: 214.0 / 255.0, blue: 10.0 / 255.0)
```

and in the comment above `run(for:)`: `None of them is the alert red or the finished mint.` becomes `None of them is the alert amber or the finished mint; OpenCode's yellow never meets the amber, as OpenCode never needs input.`

- [ ] **Step 2: Build and render**

Run the build command, then the render command from Task 1 Step 6. Read `build/render/status-marks.png`, `build/render/collapsed-faces.png` and `build/render/expanded-agents.png`: the knock, ripple, rim light, row bar and `Needs input` label are amber; nothing is red.

- [ ] **Step 3: Commit and push**

```bash
git add Symbiodock/Island/Agents/AgentPalette.swift
git commit -m "feat(agents): show a waiting session in amber" -m "Red made a question look like a failure."
git push origin main
```

---

### Task 3: Clear the question look at once

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/ScanPacing.swift`
- Create: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/ScanPacingTests.swift`
- Create: `Symbiodock/Agents/ScanSignal.swift`
- Create: `Symbiodock/Agents/SessionFolderWatcher.swift`
- Modify: `Symbiodock/Agents/AgentSessionCoordinator.swift`
- Modify: `Symbiodock/Agents/AgentProviders.swift`
- Modify: `Symbiodock/App/AppDelegate.swift:88-98`

**Interfaces:**
- Produces: `ScanPacing.delay(sinceLastStart: Date?, now: Date) -> TimeInterval`, `ScanPacing.minimumGap = 0.25`; `ScanSignal.fire()`, `ScanSignal.wait(upTo: Duration) async -> Bool`; `SessionFolderWatcher(folder:onChange:)`, `.start() -> Bool`, `.stop()`; `AgentProviders.wakeFolders() -> [URL]`; `AgentSessionCoordinator.init(providers:wakeFolders:isWatching:onUpdate:)`.

- [ ] **Step 1: Write the failing pacing tests**

`ScanPacingTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct ScanPacingTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func theFirstScanStartsAtOnce() {
        #expect(ScanPacing.delay(sinceLastStart: nil, now: start) == 0)
    }

    @Test func aScanTooSoonAfterTheLastWaitsOutTheGap() {
        let delay = ScanPacing.delay(sinceLastStart: start, now: start.addingTimeInterval(0.1))
        #expect(abs(delay - 0.15) < 1e-9)
    }

    @Test func aScanLongAfterTheLastStartsAtOnce() {
        #expect(ScanPacing.delay(sinceLastStart: start, now: start.addingTimeInterval(1)) == 0)
    }

    @Test func aClockThatWentBackNeverWaitsLongerThanTheGap() {
        let delay = ScanPacing.delay(sinceLastStart: start, now: start.addingTimeInterval(-60))
        #expect(delay == ScanPacing.minimumGap)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter ScanPacingTests`
Expected: FAIL, `cannot find 'ScanPacing' in scope`.

- [ ] **Step 3: Write `ScanPacing`**

```swift
import Foundation

/// When the next scan for agent sessions may start. A changed session file wakes the
/// scanner; a burst of changes must not turn into a burst of scans.
public enum ScanPacing {
    /// Two scans never start closer together than this.
    public static let minimumGap: TimeInterval = 0.25

    /// How long a scan asked for at `now` waits, the last one having started at `lastStart`.
    public static func delay(sinceLastStart lastStart: Date?, now: Date) -> TimeInterval {
        guard let lastStart else { return 0 }
        return min(max(minimumGap - now.timeIntervalSince(lastStart), 0), minimumGap)
    }
}
```

- [ ] **Step 4: Run the core tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: PASS.

- [ ] **Step 5: Write `ScanSignal`**

`Symbiodock/Agents/ScanSignal.swift`:

```swift
import Foundation

/// Lets the session scanner sleep between scans and be woken early. A wake that comes
/// while no one waits is kept for the next wait.
@MainActor
final class ScanSignal {
    private var waiter: CheckedContinuation<Bool, Never>?
    private var pending = false
    /// Tells a wait's timer from the timer of a wait that already ended.
    private var generation = 0

    /// Ends the current wait at once, or the next one if no one waits.
    func fire() {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: true)
        } else {
            pending = true
        }
    }

    /// Waits until `fire()` or until `timeout` has passed. True if it was fired.
    func wait(upTo timeout: Duration) async -> Bool {
        if pending {
            pending = false
            return true
        }
        generation += 1
        let mine = generation
        return await withCheckedContinuation { continuation in
            waiter = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.timeOut(mine)
            }
        }
    }

    private func timeOut(_ wait: Int) {
        guard wait == generation, let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: false)
    }
}
```

- [ ] **Step 6: Write `SessionFolderWatcher`**

`Symbiodock/Agents/SessionFolderWatcher.swift`:

```swift
import CoreServices
import Foundation

/// Calls back on the main actor soon after anything in a folder changes, so that a
/// session's new status is seen at once instead of on the next timed scan. It only
/// listens: FSEvents reports the changes without the folder being opened or written.
@MainActor
final class SessionFolderWatcher {
    /// Carries the handler into the C callback, which runs on `queue`.
    private final class Relay: Sendable {
        let onChange: @MainActor @Sendable () -> Void

        init(_ onChange: @escaping @MainActor @Sendable () -> Void) {
            self.onChange = onChange
        }

        func fire() {
            let onChange = onChange
            Task { @MainActor in onChange() }
        }
    }

    private let path: String
    private let relay: Relay
    private let queue = DispatchQueue(label: "com.yigtwxx.Symbiodock.session-folder", qos: .utility)
    private var stream: FSEventStreamRef?

    init(folder: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        path = folder.path
        relay = Relay(onChange)
    }

    /// Starts listening unless it already does. False while the folder does not exist;
    /// the caller tries again later.
    @discardableResult
    func start() -> Bool {
        if stream != nil { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        // The watcher outlives its stream (`stop()` ends it), so the relay needs no retain.
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(relay).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Relay>.fromOpaque(info).takeUnretainedValue().fire()
            },
            &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags)
        else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
```

- [ ] **Step 7: Wake the coordinator**

In `AgentProviders.swift` add, inside `enum AgentProviders`:

```swift
    /// Folders whose changes should start a scan at once: Claude Code writes a session's
    /// file there the moment its status changes.
    static func wakeFolders() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".claude/sessions", isDirectory: true)]
    }
```

In `AgentSessionCoordinator.swift`: add the stored properties and the parameter, and replace `start()` and `stop()`:

```swift
    private let wakeFolders: [URL]
    private let signal = ScanSignal()
    private var watchers: [SessionFolderWatcher] = []

    /// - Parameter wakeFolders: folders whose changes start a scan at once.
    /// - Parameter isWatching: whether the Agents tab is on screen; then the scan runs every second.
    init(
        providers: [any AgentSessionProvider],
        wakeFolders: [URL] = [],
        isWatching: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor ([AgentSession]) -> Void
    ) {
        self.providers = providers
        self.wakeFolders = wakeFolders
        self.isWatching = isWatching
        self.onUpdate = onUpdate
    }

    func start() {
        guard task == nil else { return }
        let providers = providers
        let scanner = ProcessScanner()
        let signal = signal
        watchers = wakeFolders.map { SessionFolderWatcher(folder: $0) { signal.fire() } }
        task = Task { [weak self] in
            var lastCount = -1
            var lastStart: Date?
            while !Task.isCancelled {
                // However often it is woken, two scans never start too close together.
                let gap = ScanPacing.delay(sinceLastStart: lastStart, now: Date())
                if gap > 0 { try? await Task.sleep(for: .seconds(gap)) }
                lastStart = Date()
                // A folder that did not exist yet may have appeared since.
                self?.watchers.forEach { $0.start() }
                // One scan at a time: the next starts only after this one has ended.
                let sessions = await Self.scan(providers, with: scanner)
                guard !Task.isCancelled, let self else { return }
                self.onUpdate(sessions)
                if sessions.count != lastCount {
                    lastCount = sessions.count
                    let tools = Set(sessions.map(\.tool.rawValue)).sorted().joined(separator: ",")
                    Self.log.notice("sessions: \(sessions.count, privacy: .public) [\(tools, privacy: .public)]")
                }
                // Until the next scan is due. A changed session file, or the Agents tab
                // being looked at, ends the wait early.
                for _ in 0..<Self.restingInterval {
                    if await signal.wait(upTo: .seconds(1)) { break }
                    if Task.isCancelled || self.isWatching() { break }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        watchers.forEach { $0.stop() }
        watchers = []
        // Ends a wait at once, so that the cancelled loop returns now.
        signal.fire()
    }
```

In `AppDelegate.startAgents()` pass the folders:

```swift
        let agents = AgentSessionCoordinator(
            providers: AgentProviders.all(),
            wakeFolders: AgentProviders.wakeFolders(),
            isWatching: { [weak self] in
```

- [ ] **Step 8: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **` with no new warnings (`xcodebuild ... 2>&1 | grep -i "warning:" | grep -v "appintents"` prints nothing new).

- [ ] **Step 9: Measure the delay live**

1. `pkill -x Symbiodock; open build/Build/Products/Debug/Symbiodock.app`
2. In another terminal, start `claude` in any folder and ask it: "Ask me a yes/no question with the AskUserQuestion tool."
3. While the question is open, run `ls -l ~/.claude/sessions/*.json` and note the file. Answer the question and watch the island (collapsed, not hovered).
4. Expected: the amber mark and rim light go within about a third of a second. Record what was seen in the task report; this is also checklist item 7.

- [ ] **Step 10: Check CPU stays at rest**

With no agent busy and the island collapsed: `top -l 3 -pid $(pgrep -x Symbiodock) -stats cpu | tail -1`
Expected: `0.0` (one of the three samples may show a scan; the last should be 0).

- [ ] **Step 11: Commit and push**

```bash
git add Packages/SymbiodockCore Symbiodock/Agents Symbiodock/App/AppDelegate.swift
git commit -m "perf(agents): scan as soon as a session file changes" -m "Claude Code writes the new status within 0.1 s of an answer, but the island looked only every 3 s, so the question lingered for up to 3 s."
git push origin main
```

---

### Task 4: Subagents in the model and the board

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentBranches.swift`
- Create: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentBranchesTests.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSession.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSessionBoard.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentLabels.swift`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentSessionBoardTests.swift`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentLabelsTests.swift`

**Interfaces:**
- Produces:
  - `public struct AgentSubagent: Identifiable, Equatable, Sendable { id: String; title: String; isFinished: Bool; since: Date }` with `public init(id:title:isFinished:since:)`.
  - `AgentSession.subagents: [AgentSubagent]` (`public var`, init parameter `subagents: [AgentSubagent] = []` after `hostAppPID`).
  - `public enum AgentBranch: Identifiable, Equatable, Sendable { case subagent(AgentSubagent); case more(Int) }`, `id` is `"s:<id>"` or `"more"`.
  - `AgentBranches.lines(for: [AgentSubagent], state: AgentRowState, turnStart: Date?) -> [AgentBranch]`, `AgentBranches.maximumLines = 3`.
  - `AgentRow.branches: [AgentBranch]`.
  - `AgentLabels.branchStatus(_: AgentSubagent, now: Date) -> String`, `AgentLabels.branchDescription(_: AgentBranch, now: Date) -> String`.

- [ ] **Step 1: Write the failing branch tests**

`AgentBranchesTests.swift`:

```swift
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
```

- [ ] **Step 2: Write the failing board tests**

In `AgentSessionBoardTests.swift`, change the helper to take subagents and add a branch reader:

```swift
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
```

and add the tests:

```swift
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
                sub("early", finished: true, at: 5), sub("late", finished: true, at: 12),
            ]),
        ])
        #expect(branchIDs(board) == ["late"])
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
```

- [ ] **Step 3: Write the failing label tests**

Append to `AgentLabelsTests.swift` (inside the existing test struct):

```swift
    @Test func aBranchSaysHowLongItRunsOrThatItIsDone() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let working = AgentSubagent(id: "w", title: "Map the views", isFinished: false, since: now.addingTimeInterval(-125))
        let done = AgentSubagent(id: "d", title: "Read the spec", isFinished: true, since: now.addingTimeInterval(-30))
        #expect(AgentLabels.branchStatus(working, now: now) == "2m")
        #expect(AgentLabels.branchStatus(done, now: now) == "Done")
        #expect(AgentLabels.branchDescription(.subagent(working), now: now) == "Subagent Map the views, working 2m")
        #expect(AgentLabels.branchDescription(.subagent(done), now: now) == "Subagent Read the spec, done")
        #expect(AgentLabels.branchDescription(.more(3), now: now) == "3 more subagents")
    }
```

- [ ] **Step 4: Run them to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: FAIL to compile, `cannot find 'AgentSubagent' in scope`.

- [ ] **Step 5: Write `AgentBranches.swift`**

```swift
import Foundation

/// One subagent of a session.
public struct AgentSubagent: Identifiable, Equatable, Sendable {
    /// The tool's own id for the subagent.
    public let id: String
    public let title: String
    public let isFinished: Bool
    /// When it started while it works; when it finished once it is done.
    public let since: Date

    public init(id: String, title: String, isFinished: Bool, since: Date) {
        self.id = id
        self.title = title
        self.isFinished = isFinished
        self.since = since
    }
}

/// A line below a session's row.
public enum AgentBranch: Identifiable, Equatable, Sendable {
    case subagent(AgentSubagent)
    /// The subagents that did not fit.
    case more(Int)

    public var id: String {
        switch self {
        case .subagent(let subagent): "s:\(subagent.id)"
        case .more: "more"
        }
    }
}

/// Which subagents a row shows below itself, and in what order.
public enum AgentBranches {
    /// The most lines below one row.
    public static let maximumLines = 3

    /// Working subagents, oldest first; then, while the parent works or waits, the ones
    /// that finished during its current turn, newest first. More than `maximumLines`:
    /// the first lines and a count of the rest.
    public static func lines(
        for subagents: [AgentSubagent], state: AgentRowState, turnStart: Date?
    ) -> [AgentBranch] {
        let working = subagents
            .filter { !$0.isFinished }
            .sorted { ($0.since, $0.id) < ($1.since, $1.id) }
        var finished: [AgentSubagent] = []
        if let turnStart, isActive(state) {
            finished = subagents
                .filter { $0.isFinished && $0.since >= turnStart }
                .sorted { $0.since != $1.since ? $0.since > $1.since : $0.id < $1.id }
        }
        let shown = working + finished
        guard shown.count > maximumLines else { return shown.map(AgentBranch.subagent) }
        let kept = maximumLines - 1
        return shown.prefix(kept).map(AgentBranch.subagent) + [.more(shown.count - kept)]
    }

    private static func isActive(_ state: AgentRowState) -> Bool {
        switch state {
        case .working, .needsInput: true
        case .finished, .running, .idle: false
        }
    }
}
```

- [ ] **Step 6: Add `subagents` to `AgentSession`**

In `AgentSession.swift`, after `public var hostAppPID: Int32?`:

```swift
    /// Its subagents that are still worth showing; empty for a tool that has none.
    public var subagents: [AgentSubagent]
```

and the init becomes:

```swift
    public init(
        id: String, tool: AgentTool, title: String, projectPath: String?,
        activity: AgentActivity, since: Date, pid: Int32?, hostAppPID: Int32? = nil,
        subagents: [AgentSubagent] = []
    ) {
        self.id = id
        self.tool = tool
        self.title = title
        self.projectPath = projectPath
        self.activity = activity
        self.since = since
        self.pid = pid
        self.hostAppPID = hostAppPID
        self.subagents = subagents
    }
```

- [ ] **Step 7: Give the board turn starts and rows branches**

In `AgentSessionBoard.swift`:

`AgentRow` becomes:

```swift
public struct AgentRow: Identifiable, Equatable, Sendable {
    public let session: AgentSession
    public let state: AgentRowState
    /// The lines below the row: its subagents.
    public let branches: [AgentBranch]
    public var id: String { session.id }
}
```

Add beside `finishedIDs`:

```swift
    /// When each active session's current turn began: its `since` on the update where it
    /// became active. A question in the middle of the turn does not move it.
    private var turnStarts: [String: Date] = [:]
```

In `update(_:)`, the `.working, .needsInput` case becomes:

```swift
            case .working, .needsInput:
                active.insert(session.id)
                finishedIDs.remove(session.id)
                if !activeIDs.contains(session.id) || turnStarts[session.id] == nil {
                    turnStarts[session.id] = session.since
                }
```

and after `finishedIDs.formIntersection(seen)`:

```swift
        turnStarts = turnStarts.filter { active.contains($0.key) }
```

`rebuild(from:)` builds rows with branches:

```swift
    private mutating func rebuild(from sessions: [AgentSession]) {
        rows = sessions
            .map { session in
                let state = state(of: session)
                return AgentRow(
                    session: session, state: state,
                    branches: AgentBranches.lines(
                        for: session.subagents, state: state, turnStart: turnStarts[session.id]))
            }
            .sorted { lhs, rhs in
                if lhs.state.rank != rhs.state.rank { return lhs.state.rank < rhs.state.rank }
                if lhs.session.since != rhs.session.since {
                    return lhs.session.since > rhs.session.since
                }
                return lhs.id < rhs.id
            }
    }
```

- [ ] **Step 8: Add the branch labels**

In `AgentLabels.swift`, inside the enum:

```swift
    /// A subagent's trailing text: how long it has run, or `Done`.
    public static func branchStatus(_ subagent: AgentSubagent, now: Date) -> String {
        subagent.isFinished ? "Done" : duration(now.timeIntervalSince(subagent.since))
    }

    /// What VoiceOver reads for a line below a row.
    public static func branchDescription(_ branch: AgentBranch, now: Date) -> String {
        switch branch {
        case .subagent(let subagent):
            subagent.isFinished
                ? "Subagent \(subagent.title), done"
                : "Subagent \(subagent.title), working \(branchStatus(subagent, now: now))"
        case .more(let count):
            "\(count) more subagents"
        }
    }
```

- [ ] **Step 9: Run the core tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: PASS, all old and new tests.

- [ ] **Step 10: Build the app**

Run the build command. Expected: `** BUILD SUCCEEDED **` (nothing in the app builds `AgentRow` itself; `grep -rn "AgentRow(" Symbiodock` prints nothing).

- [ ] **Step 11: Commit and push**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(agents): model subagents as branches of a session row" -m "A row needs to know which subagents to show: working ones always, finished ones only during the parent's current turn, three lines at most."
git push origin main
```

---

### Task 5: Read Claude Code subagent files

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/ClaudeSubagentParser.swift`
- Create: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/ClaudeSubagentParserTests.swift`

**Interfaces:**
- Consumes: `AgentSubagent` (Task 4), `ClaudeSessionParser.transcriptRelativePath(cwd:sessionID:)`.
- Produces:
  - `public struct ClaudeSubagentMeta: Equatable, Sendable { title: String; isFinished: Bool; toolUseID: String?; isBackground: Bool }`
  - `ClaudeSubagentParser.maximumMetaSize = 16 * 1024`, `.quietLimit = 600`, `.finishedListing = 7200`
  - `ClaudeSubagentParser.folderRelativePath(cwd: String, sessionID: String) -> String?`
  - `ClaudeSubagentParser.agentID(metaFileName: String) -> String?`
  - `ClaudeSubagentParser.meta(from: Data) -> ClaudeSubagentMeta?`
  - `ClaudeSubagentParser.endedIDs(_ candidates: [(id: String, meta: ClaudeSubagentMeta)], inTail: Data) -> Set<String>`
  - `ClaudeSubagentParser.subagent(id:meta:started:lastWrite:metaModified:hasEnded:now:) -> AgentSubagent?`

- [ ] **Step 1: Write the failing tests**

`ClaudeSubagentParserTests.swift` (fixtures in the shapes seen on 2026-11-15, version 2.1.325, with no real user content):

```swift
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
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter ClaudeSubagentParserTests`
Expected: FAIL, `cannot find 'ClaudeSubagentParser' in scope`.

- [ ] **Step 3: Write `ClaudeSubagentParser.swift`**

```swift
import Foundation

/// What a Claude Code subagent's meta file says.
public struct ClaudeSubagentMeta: Equatable, Sendable {
    public let title: String
    /// Written when it ends normally; absent while it runs and after it was stopped.
    public let isFinished: Bool
    /// The parent's `tool_use` that started it.
    public let toolUseID: String?
    /// Started in the background: its end is announced by a task notification.
    public let isBackground: Bool
}

/// Reads `~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.meta.json` and the
/// signs in the parent's transcript that a subagent has ended.
public enum ClaudeSubagentParser {
    public static let maximumMetaSize = 16 * 1024
    /// A subagent that has not finished and whose transcript has been quiet this long
    /// has ended without saying so.
    public static let quietLimit: TimeInterval = 10 * 60
    /// A finished subagent older than this is not passed on.
    public static let finishedListing: TimeInterval = 2 * 60 * 60

    /// Below `~/.claude`, next to the session's transcript.
    public static func folderRelativePath(cwd: String, sessionID: String) -> String? {
        ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
            .map { String($0.dropLast(".jsonl".count)) + "/subagents" }
    }

    /// The id in `agent-<id>.meta.json`; nil for any other name, or an id that could
    /// leave the folder.
    public static func agentID(metaFileName name: String) -> String? {
        let prefix = "agent-", suffix = ".meta.json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
              name.count > prefix.count + suffix.count
        else { return nil }
        let id = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard id.unicodeScalars.allSatisfy({ isLetterOrDigit($0) || $0 == "-" }) else { return nil }
        return id
    }

    public static func meta(from data: Data) -> ClaudeSubagentMeta? {
        guard data.count <= maximumMetaSize,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let title = [object["description"], object["agentType"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return ClaudeSubagentMeta(
            title: title ?? "Subagent",
            isFinished: (object["finished"] as? Bool) == true,
            toolUseID: object["toolUseId"] as? String,
            isBackground: object["requestShape"] as? String == "background")
    }

    /// The candidates the parent's transcript shows as ended: a task notification naming
    /// a background subagent, or a tool result answering the `tool_use` that started any
    /// other. (A background subagent's tool result comes at its launch.)
    public static func endedIDs(
        _ candidates: [(id: String, meta: ClaudeSubagentMeta)], inTail data: Data
    ) -> Set<String> {
        var ended = Set<String>()
        for (id, meta) in candidates {
            let marker: String
            if meta.isBackground {
                marker = "<task-id>\(id)</task-id>"
            } else if let toolUseID = meta.toolUseID, !toolUseID.isEmpty {
                marker = "\"tool_use_id\":\"\(toolUseID)\""
            } else {
                continue
            }
            if data.range(of: Data(marker.utf8)) != nil { ended.insert(id) }
        }
        return ended
    }

    /// The subagent as the island shows it, or nil once it is no longer shown.
    /// - Parameters:
    ///   - started: when its transcript was created, or its meta file without one.
    ///   - lastWrite: its transcript's last change.
    ///   - metaModified: its meta file's last change: the finish, once it has finished.
    ///   - hasEnded: the parent's transcript shows that it ended.
    public static func subagent(
        id: String, meta: ClaudeSubagentMeta, started: Date, lastWrite: Date,
        metaModified: Date, hasEnded: Bool, now: Date
    ) -> AgentSubagent? {
        if meta.isFinished {
            guard now.timeIntervalSince(metaModified) <= finishedListing else { return nil }
            return AgentSubagent(id: id, title: meta.title, isFinished: true, since: metaModified)
        }
        guard !hasEnded, now.timeIntervalSince(lastWrite) <= quietLimit else { return nil }
        return AgentSubagent(id: id, title: meta.title, isFinished: false, since: started)
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9": true
        default: false
        }
    }
}
```

- [ ] **Step 4: Run the core tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: PASS.

- [ ] **Step 5: Commit and push**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(agents): read Claude Code subagent meta files" -m "Claude Code writes a meta file per subagent and adds finished when it ends; a stopped one never gets it, so the parent's transcript is the second sign."
git push origin main
```

---

### Task 6: Claude Code provider lists subagents

**Files:**
- Modify: `Symbiodock/Agents/FileReading.swift` (`FileStamp`, `stamp(of:)`)
- Modify: `Symbiodock/Agents/ClaudeCodeProvider.swift`

**Interfaces:**
- Consumes: everything `ClaudeSubagentParser` produces (Task 5), `AgentSession.subagents` (Task 4).
- Produces: `FileStamp.created: Date`; Claude Code sessions carry `subagents`.

- [ ] **Step 1: Give `FileStamp` the creation time**

In `FileReading.swift`:

```swift
/// A file's size and times: enough to tell whether it has to be read again.
struct FileStamp: Equatable, Sendable {
    let size: Int
    let modified: Date
    /// When the file was created. A file replaced by a rename gets a new one.
    let created: Date
}
```

and in `stamp(of:)`:

```swift
    static func stamp(of url: URL) -> FileStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        func date(_ time: timespec) -> Date {
            Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
        }
        return FileStamp(
            size: Int(info.st_size), modified: date(info.st_mtimespec), created: date(info.st_birthtimespec))
    }
```

`grep -rn "FileStamp(" Symbiodock` must show only this call.

- [ ] **Step 2: Rewrite `ClaudeCodeProvider.swift`**

Keep `question(of:remembering:)` and `isLive(_:modified:among:)` exactly as they are today. Replace the rest of the file's top part so that it reads:

```swift
import Darwin
import Foundation
import SymbiodockCore

/// Claude Code keeps one small JSON file per running session in `~/.claude/sessions`,
/// with its name, folder and whether it is busy, idle or waiting for the user. Beside each
/// session's transcript, a `subagents` folder holds a small meta file per subagent.
actor ClaudeCodeProvider: AgentSessionProvider {
    nonisolated let tool = AgentTool.claudeCode
    /// `~/.claude`
    private let home: URL

    /// What was read from a waiting session's transcript, until the file changes.
    private struct Asked {
        let stamp: FileStamp
        let question: String?
    }

    /// What was read from a subagent's meta file, until the file changes.
    private struct MetaEntry {
        let stamp: FileStamp
        let meta: ClaudeSubagentMeta?
    }

    /// The subagents a parent's transcript showed as ended, as of the transcript's stamp.
    private struct Ends {
        let stamp: FileStamp
        let ended: Set<String>
    }

    /// What one scan read or kept; whatever belongs to sessions that are gone is dropped.
    private struct Kept {
        var asked: [String: Asked] = [:]
        var metas: [String: MetaEntry] = [:]
        var ends: [String: Ends] = [:]
    }

    private var asked: [String: Asked] = [:]
    private var metas: [String: MetaEntry] = [:]
    private var ends: [String: Ends] = [:]

    init(home: URL) {
        self.home = home
    }

    func sessions(in context: AgentScanContext) async -> [AgentSession] {
        let directory = home.appendingPathComponent("sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        else {
            asked.removeAll()
            metas.removeAll()
            ends.removeAll()
            return []
        }

        var kept = Kept()
        defer {
            asked = kept.asked
            metas = kept.metas
            ends = kept.ends
        }
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let stamp = FileReading.stamp(of: url),
                  let data = FileReading.whole(url, maxBytes: ClaudeSessionParser.maximumFileSize),
                  let record = ClaudeSessionParser.record(from: data),
                  Self.isLive(record.pid, modified: stamp.modified, among: context.processes),
                  var session = ClaudeSessionParser.session(
                      from: record,
                      prompt: record.status == "waiting"
                          ? question(of: record, remembering: &kept.asked) : nil,
                      fallbackSince: stamp.modified)
            else { return nil }
            session.subagents = subagents(of: record, now: context.now, remembering: &kept)
            return session
        }
    }

    /// The session's subagents still worth showing. A meta file is parsed again only when
    /// it changed. The parent's transcript is searched only while a subagent has not
    /// finished, and again only when the transcript changed.
    private func subagents(
        of record: ClaudeSessionRecord, now: Date, remembering kept: inout Kept
    ) -> [AgentSubagent] {
        guard let cwd = record.cwd, let sessionID = record.sessionID,
              let folderPath = ClaudeSubagentParser.folderRelativePath(cwd: cwd, sessionID: sessionID),
              let transcriptPath = ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
        else { return [] }
        let folder = home.appendingPathComponent(folderPath, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }

        var found: [(id: String, meta: ClaudeSubagentMeta, stamp: FileStamp)] = []
        for name in names {
            guard let id = ClaudeSubagentParser.agentID(metaFileName: name) else { continue }
            let url = folder.appendingPathComponent(name)
            guard let stamp = FileReading.stamp(of: url) else { continue }
            let entry = metas[url.path].flatMap { $0.stamp == stamp ? $0 : nil }
                ?? MetaEntry(
                    stamp: stamp,
                    meta: FileReading.whole(url, maxBytes: ClaudeSubagentParser.maximumMetaSize)
                        .flatMap(ClaudeSubagentParser.meta(from:)))
            kept.metas[url.path] = entry
            guard let meta = entry.meta else { continue }
            found.append((id, meta, stamp))
        }

        let open = found.filter { !$0.meta.isFinished }.map { (id: $0.id, meta: $0.meta) }
        let ended = open.isEmpty
            ? []
            : endedIDs(
                among: open, transcript: home.appendingPathComponent(transcriptPath),
                remembering: &kept.ends)

        return found.compactMap { item in
            // A finished subagent's times come from its meta file alone.
            let written = item.meta.isFinished
                ? nil : FileReading.stamp(of: folder.appendingPathComponent("agent-\(item.id).jsonl"))
            return ClaudeSubagentParser.subagent(
                id: item.id, meta: item.meta,
                started: written?.created ?? item.stamp.created,
                lastWrite: written?.modified ?? item.stamp.modified,
                metaModified: item.stamp.modified,
                hasEnded: ended.contains(item.id), now: now)
        }
    }

    /// Which open subagents the parent's transcript shows as ended. Once seen ended, a
    /// subagent stays ended though the sign scrolls out of the transcript's tail.
    private func endedIDs(
        among open: [(id: String, meta: ClaudeSubagentMeta)], transcript url: URL,
        remembering kept: inout [String: Ends]
    ) -> Set<String> {
        let openIDs = Set(open.map(\.id))
        let known = ends[url.path]
        guard let stamp = FileReading.stamp(of: url) else {
            return (known?.ended ?? []).intersection(openIDs)
        }
        if let known, known.stamp == stamp {
            kept[url.path] = known
            return known.ended.intersection(openIDs)
        }
        let seen = FileReading.tail(of: url, maxBytes: ClaudeTranscriptPromptReader.tailSize)
            .map { ClaudeSubagentParser.endedIDs(open, inTail: $0) } ?? []
        let ended = (known?.ended ?? []).intersection(openIDs).union(seen)
        kept[url.path] = Ends(stamp: stamp, ended: ended)
        return ended
    }
```

`question(of:remembering:)` keeps its signature `remembering kept: inout [String: Asked]`; it is now passed `&kept.asked`.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: See it live**

1. `pkill -x Symbiodock; open build/Build/Products/Debug/Symbiodock.app`
2. In this Claude Code session, start a background subagent that sleeps 60 s (`python3 -c "import time; time.sleep(60)"`).
3. Hover the island, Agents tab. Expected: this session's row has a branch with the subagent's description and `<1m`, then `1m`.
4. When it ends: the branch shows `Done ✓` in mint while the session is still busy, and disappears once the session is idle.
5. Start another and stop it with `TaskStop`. Expected: its branch disappears within a scan.
Record what was seen in the task report.

- [ ] **Step 5: Commit and push**

```bash
git add Symbiodock/Agents
git commit -m "feat(agents): list Claude Code subagents under their session" -m "The owner wants to see a session's subagents while they run; their meta files say what each one is and whether it finished."
git push origin main
```

---

### Task 7: Codex subagents

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/CodexRolloutParser.swift`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/CodexRolloutParserTests.swift`
- Modify: `Symbiodock/Agents/CodexProvider.swift:31-55`

**Interfaces:**
- Consumes: `AgentSubagent` (Task 4).
- Produces: `CodexThreadMeta.parentID: String?`, `.subagentTitle: String?`, `.started: Date?` (init parameters with `nil` defaults after `originator`); `CodexTurnState.wasAborted: Bool` (init parameter `wasAborted: Bool = false`); `CodexRolloutParser.subagentQuietLimit = 600`; `CodexRolloutParser.subagent(meta:state:modified:now:) -> AgentSubagent?`; `CodexRolloutParser.rootID(of:parents:listed:) -> String?`.

- [ ] **Step 1: Write the failing tests**

Add to `CodexRolloutParserTests.swift`:

```swift
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

    @Test func aSubagentHangsUnderTheListedThreadItDescendsFrom() {
        let parents = ["c": "b", "b": "a", "x": "y", "y": "x"]
        #expect(CodexRolloutParser.rootID(of: "c", parents: parents, listed: ["a"]) == "a")
        #expect(CodexRolloutParser.rootID(of: "b", parents: parents, listed: ["a"]) == "a")
        #expect(CodexRolloutParser.rootID(of: "c", parents: parents, listed: []) == nil)
        #expect(CodexRolloutParser.rootID(of: "x", parents: parents, listed: ["a"]) == nil)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter CodexRolloutParserTests`
Expected: FAIL to compile, `value of type 'CodexThreadMeta' has no member 'parentID'`.

- [ ] **Step 3: Extend the parser**

`CodexThreadMeta` becomes:

```swift
public struct CodexThreadMeta: Equatable, Sendable {
    public let id: String
    public let cwd: String?
    /// A thread spawned by another thread; it is shown as a branch of its parent.
    public let isSubagent: Bool
    /// "Codex Desktop", ...
    public let originator: String?
    /// The thread that spawned this one.
    public let parentID: String?
    /// A subagent's name, from its agent path or nickname.
    public let subagentTitle: String?
    /// When the thread was created.
    public let started: Date?

    public init(
        id: String, cwd: String?, isSubagent: Bool, originator: String?,
        parentID: String? = nil, subagentTitle: String? = nil, started: Date? = nil
    ) {
        self.id = id
        self.cwd = cwd
        self.isSubagent = isSubagent
        self.originator = originator
        self.parentID = parentID
        self.subagentTitle = subagentTitle
        self.started = started
    }
}
```

`CodexTurnState` becomes:

```swift
public struct CodexTurnState: Equatable, Sendable {
    public let isWorking: Bool
    public let since: Date
    /// The last turn was stopped rather than completed.
    public let wasAborted: Bool

    public init(isWorking: Bool, since: Date, wasAborted: Bool = false) {
        self.isWorking = isWorking
        self.since = since
        self.wasAborted = wasAborted
    }
}
```

In `CodexRolloutParser`, add after `workingListing`:

```swift
    /// A working subagent whose file has not changed for this long is taken for abandoned.
    public static let subagentQuietLimit: TimeInterval = 10 * 60
```

`meta(fromHead:)` becomes:

```swift
    public static func meta(fromHead data: Data) -> CodexThreadMeta? {
        guard let line = data.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = payload["id"] as? String, !id.isEmpty
        else { return nil }
        let source = payload["source"] as? [String: Any]
        let spawn = (source?["subagent"] as? [String: Any])?["thread_spawn"] as? [String: Any]
        let parent = [spawn?["parent_thread_id"], payload["parent_thread_id"]]
            .compactMap { $0 as? String }
            .first { !$0.isEmpty }
        let stamp = (payload["timestamp"] as? String) ?? (object["timestamp"] as? String)
        return CodexThreadMeta(
            id: id,
            cwd: payload["cwd"] as? String,
            isSubagent: parent != nil || source?["subagent"] != nil,
            originator: payload["originator"] as? String,
            parentID: parent,
            subagentTitle: subagentTitle(spawn),
            started: stamp.flatMap(timestamp))
    }

    /// "/root/notch_market_research" → "notch market research"; else the nickname.
    static func subagentTitle(_ spawn: [String: Any]?) -> String? {
        guard let spawn else { return nil }
        if let path = spawn["agent_path"] as? String {
            let name = (path as NSString).lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && name != "/" { return name }
        }
        let nickname = (spawn["agent_nickname"] as? String)?.trimmingCharacters(in: .whitespaces)
        return nickname?.isEmpty == false ? nickname : nil
    }
```

In `turnState(inTail:)` the assignment becomes:

```swift
            state = CodexTurnState(
                isWorking: type == "task_started", since: date, wasAborted: type == "turn_aborted")
```

Add after `session(meta:state:title:pid:)`:

```swift
    /// A subagent as its parent's branch, or nil if it is not shown: it was stopped, it
    /// went quiet in the middle of a turn, or it finished long ago.
    public static func subagent(
        meta: CodexThreadMeta, state: CodexTurnState, modified: Date, now: Date
    ) -> AgentSubagent? {
        guard meta.isSubagent, !state.wasAborted else { return nil }
        let title = meta.subagentTitle ?? "Subagent"
        if state.isWorking {
            guard now.timeIntervalSince(modified) <= subagentQuietLimit else { return nil }
            return AgentSubagent(id: meta.id, title: title, isFinished: false, since: meta.started ?? state.since)
        }
        guard now.timeIntervalSince(modified) <= idleListing else { return nil }
        return AgentSubagent(id: meta.id, title: title, isFinished: true, since: state.since)
    }

    /// The listed thread a subagent descends from, following `parents` (thread id →
    /// parent id); nil if none of its ancestors is listed.
    public static func rootID(
        of id: String, parents: [String: String], listed: Set<String>
    ) -> String? {
        var current = id
        var seen: Set<String> = [id]
        while let parent = parents[current] {
            if listed.contains(parent) { return parent }
            guard seen.insert(parent).inserted else { return nil }
            current = parent
        }
        return nil
    }
```

- [ ] **Step 4: Run the core tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: PASS.

- [ ] **Step 5: Attach subagents in the provider**

In `CodexProvider.sessions(in:)`, replace the part from `var sessions: [AgentSession] = []` to `return sessions` with:

```swift
        var listed: [(meta: CodexThreadMeta, session: AgentSession)] = []
        var children: [(id: String, subagent: AgentSubagent)] = []
        var parents: [String: String] = [:]
        var live: [String: Entry] = [:]
        for url in recentRollouts() {
            guard let stamp = FileReading.stamp(of: url),
                  context.now.timeIntervalSince(stamp.modified) <= CodexRolloutParser.workingListing
            else { continue }
            let entry = entry(for: url, stamp: stamp)
            live[url.path] = entry
            guard let meta = entry.meta else { continue }
            if let parent = meta.parentID { parents[meta.id] = parent }
            guard let state = entry.state else { continue }
            if meta.isSubagent {
                if let subagent = CodexRolloutParser.subagent(
                    meta: meta, state: state, modified: stamp.modified, now: context.now)
                {
                    children.append((meta.id, subagent))
                }
                continue
            }
            guard CodexRolloutParser.isListed(state, modified: stamp.modified, now: context.now)
            else { continue }
            listed.append((
                meta,
                CodexRolloutParser.session(
                    meta: meta, state: state, title: title(of: meta.id),
                    pid: Self.process(for: meta, among: codex))))
        }
        cache = live

        // Each subagent hangs under the listed thread it descends from.
        let listedIDs = Set(listed.map(\.meta.id))
        var branches: [String: [AgentSubagent]] = [:]
        for child in children {
            guard let root = CodexRolloutParser.rootID(of: child.id, parents: parents, listed: listedIDs)
            else { continue }
            branches[root, default: []].append(child.subagent)
        }
        return listed.map { item in
            var session = item.session
            session.subagents = branches[item.meta.id] ?? []
            return session
        }
```

- [ ] **Step 6: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit and push**

```bash
git add Packages/SymbiodockCore Symbiodock/Agents/CodexProvider.swift
git commit -m "feat(agents): list Codex subagents under their thread" -m "Codex writes each subagent to a rollout of its own that names its parent; until now those rollouts were skipped."
git push origin main
```

---

### Task 8: Branches in the Agents tab

**Files:**
- Modify: `Symbiodock/Island/Agents/AgentsContent.swift` (whole file below)
- Modify: `Symbiodock/Agents/DemoAgents.swift`
- Modify: `Symbiodock/App/DebugRender.swift` (`runIfRequested`)

**Interfaces:**
- Consumes: `AgentRow.branches`, `AgentBranch`, `AgentLabels.branchStatus`, `AgentLabels.branchDescription` (Task 4); `AgentPalette.mint`.
- Produces: demo set `SYMBIODOCK_DEMO_AGENTS=branches`; render `build/render/expanded-agents-branches.png`.

- [ ] **Step 1: Rewrite `AgentsContent.swift`**

```swift
import SwiftUI
import SymbiodockCore

/// The Agents tab: the sessions one under the other, two at a time, or an idle message.
/// A session's subagents hang below its row as branches.
struct AgentsContent: View {
    let rows: [AgentRow]
    /// Height of the header band; nothing can be shown behind it.
    let topInset: CGFloat
    let onOpen: (AgentSession) -> Void

    /// How many sessions the viewport is sized for; the rest are reached by scrolling.
    private static let visibleRows = 2
    private static let rowSpacing: CGFloat = 4
    /// Kept free below the list.
    private static let bottomMargin: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            Group {
                if rows.isEmpty {
                    idle
                } else {
                    list(available: proxy.size.height - Self.bottomMargin)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.top, topInset)
    }

    private var idle: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("No agents running")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// The blocks' heights with the spacing between them.
    private func height(of rows: some Collection<AgentRow>) -> CGFloat {
        let blocks = rows.reduce(0) { $0 + AgentRowView.height(of: $1) }
        return blocks + CGFloat(max(rows.count - 1, 0)) * Self.rowSpacing
    }

    /// As tall as the first two blocks, but never taller than the room below the header,
    /// so one or two blocks sit centred and a tall block is scrolled.
    private func list(available: CGFloat) -> some View {
        let viewport = min(height(of: rows.prefix(Self.visibleRows)), max(available, AgentRowView.rowHeight))
        let overflows = height(of: rows) > viewport + 0.5
        // The labels count minutes; they are redrawn on their own now and then.
        return TimelineView(.periodic(from: .now, by: 20)) { context in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(rows) { row in
                        AgentRowView(row: row, now: context.date, onOpen: onOpen)
                    }
                }
                .scrollTargetLayout()
            }
            // The list comes to rest on a session, never between two.
            .scrollTargetBehavior(.viewAligned)
            .frame(height: viewport)
            .mask {
                // Fading out at the lower edge says that the list goes on.
                if overflows {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.84),
                            .init(color: .black.opacity(0.25), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle()
                }
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct AgentRowView: View {
    static let rowHeight: CGFloat = 46

    /// The row and the branches below it.
    static func height(of row: AgentRow) -> CGFloat {
        rowHeight + AgentBranchLines.height(of: row.branches)
    }

    let row: AgentRow
    let now: Date
    let onOpen: (AgentSession) -> Void

    var body: some View {
        if row.session.hostAppPID != nil {
            Button {
                onOpen(row.session)
            } label: {
                block
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("Brings its app to the front")
        } else {
            block
        }
    }

    /// One scroll target: the row and its branches.
    private var block: some View {
        VStack(spacing: 0) {
            content
            if !row.branches.isEmpty {
                AgentBranchLines(branches: row.branches, now: now)
            }
        }
        .contentShape(Rectangle())
    }

    private var prompt: String? {
        if case .needsInput(let prompt) = row.state { prompt } else { nil }
    }

    private var needsInput: Bool {
        if case .needsInput = row.state { true } else { false }
    }

    private var labelColor: Color {
        switch row.state {
        case .needsInput: AgentPalette.alert
        case .finished: AgentPalette.mint
        case .working, .running, .idle: .white.opacity(0.6)
        }
    }

    /// The tool and the project folder: "Claude Code · storefront".
    private var origin: String {
        guard let project = row.session.projectName, project != row.session.title else {
            return row.session.tool.displayName
        }
        return "\(row.session.tool.displayName) · \(project)"
    }

    private var content: some View {
        HStack(spacing: 10) {
            AgentPet(tool: row.session.tool, state: row.state, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(row.state == .idle ? 0.6 : 1))
                    .lineLimit(1)
                Text(prompt ?? origin)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(prompt == nil ? 0.5 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(AgentLabels.status(row.state, since: row.session.since, now: now))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .fixedSize()
            // The status text beside it already speaks; the mark would repeat it.
            AgentStatusMark(state: row.state)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if needsInput {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AgentPalette.alert.opacity(0.12))
            }
        }
        .overlay(alignment: .leading) {
            if needsInput {
                Capsule().fill(AgentPalette.alert).frame(width: 2).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A session's subagents below its row, joined to its pet by a thin line, like a fork.
/// Nothing in it moves: the times change with the list's periodic redraw.
private struct AgentBranchLines: View {
    static let lineHeight: CGFloat = 16
    /// Below the last line, so that the next row does not touch it.
    static let bottomPadding: CGFloat = 4
    /// The connector runs under the pet's centre: the row's padding and half the pet.
    private static let connectorX: CGFloat = 10 + 18
    private static let tick: CGFloat = 8
    /// The trailing text ends where the row's label ends: the row's padding, the status
    /// mark and the spacing before it.
    private static let trailingInset: CGFloat = 10 + 14 + 10

    static func height(of branches: [AgentBranch]) -> CGFloat {
        branches.isEmpty ? 0 : CGFloat(branches.count) * lineHeight + bottomPadding
    }

    let branches: [AgentBranch]
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(branches) { branch in
                line(branch, isLast: branch.id == branches.last?.id)
            }
        }
        .padding(.bottom, Self.bottomPadding)
    }

    private func line(_ branch: AgentBranch, isLast: Bool) -> some View {
        HStack(spacing: 6) {
            Connector(x: Self.connectorX, tick: Self.tick, isLast: isLast)
                .stroke(.white.opacity(0.22), lineWidth: 1)
                .frame(width: Self.connectorX + Self.tick, height: Self.lineHeight)
            label(branch)
        }
        .padding(.trailing, Self.trailingInset)
        .frame(height: Self.lineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentLabels.branchDescription(branch, now: now))
    }

    @ViewBuilder
    private func label(_ branch: AgentBranch) -> some View {
        switch branch {
        case .subagent(let subagent):
            Text(subagent.title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(subagent.isFinished ? 0.4 : 0.7))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if subagent.isFinished {
                HStack(spacing: 3) {
                    Text(AgentLabels.branchStatus(subagent, now: now))
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AgentPalette.mint)
                .fixedSize()
            } else {
                Text(AgentLabels.branchStatus(subagent, now: now))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize()
            }
        case .more(let count):
            Text("+\(count) more")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
        }
    }
}

/// `├─` for a line with more below it, `└─` for the last.
private struct Connector: Shape {
    let x: CGFloat
    let tick: CGFloat
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY))
        path.move(to: CGPoint(x: x, y: rect.midY))
        path.addLine(to: CGPoint(x: x + tick, y: rect.midY))
        return path
    }
}

/// A row dims while it is pressed, so a click is felt.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: Give the demo sessions subagents**

In `DemoAgents.swift`, update the doc line to `` `1` all states, `working`, `finished`, `quiet`, `branches` `` and, inside `apply`, after the `session(...)` helper:

```swift
        func sub(_ id: String, _ title: String, finished: Bool = false, minutes: Double) -> AgentSubagent {
            AgentSubagent(
                id: id, title: title, isFinished: finished, since: now.addingTimeInterval(-minutes * 60))
        }
```

`ask` and `work` become `var` and get subagents:

```swift
        var ask = session(
            "a", .claudeCode, "fix-login-flow", "storefront",
            .needsInput(prompt: "Which of the two migrations should run first?"), minutes: 1)
        ask.subagents = [
            sub("a1", "Explore the auth module", minutes: 3),
            sub("a2", "Review the migration order", minutes: 0.4),
            sub("a3", "Find the flaky login test", finished: true, minutes: 0.5),
        ]
        var work = session("b", .codex, "Tune the monitor", "dotfiles", .working, minutes: 2)
        work.subagents = [
            sub("b1", "notch market research", minutes: 2),
            sub("b2", "macos feasibility research", minutes: 1),
            sub("b3", "inspect product spec", finished: true, minutes: 1.5),
            sub("b4", "fresh builder ideas", finished: true, minutes: 0.5),
        ]
```

and add a case to the `switch`:

```swift
        case "branches":
            state.setAgentSessions([work])
```

- [ ] **Step 3: Render the branches**

In `DebugRender.runIfRequested`, after the `expanded-agents-empty` write:

```swift
        let branches = IslandState()
        DemoAgents.apply("branches", to: branches)
        branches.setHovering(true)
        branches.selectTab(.agents)
        write(
            ExpandedPreview(state: branches), size: CGSize(width: 640, height: 190),
            named: "expanded-agents-branches", to: directory)
```

- [ ] **Step 4: Build, render, look**

Run the build command, then `SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`.
Read with the Read tool:
- `build/render/expanded-agents.png`: the amber `fix-login-flow` row, below it `├─ Explore the auth module 3m`, `├─ Review the migration order <1m`, `└─ Find the flaky login test Done ✓`; the line starts under the pet's centre; the next row's top shows under it with the fade.
- `build/render/expanded-agents-branches.png`: `Tune the monitor`, then `notch market research 2m`, `macos feasibility research 1m`, `└─ +2 more`.
- `build/render/expanded-agents-empty.png` and `expanded-media.png`: unchanged apart from the size.
If something is clipped or misaligned, fix the constants in `AgentBranchLines` and render again.

- [ ] **Step 5: Check CPU at rest with branches**

`pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_AGENTS=1 build/Build/Products/Debug/Symbiodock.app`, hover the island, leave the pointer on it, then: `top -l 3 -pid $(pgrep -x Symbiodock) -stats cpu | tail -1`.
Expected: about the same as before this task (the pets' wave and the status mark run in Core Animation; the branches add nothing that moves).

- [ ] **Step 6: Commit and push**

```bash
git add Symbiodock/Island/Agents/AgentsContent.swift Symbiodock/Agents/DemoAgents.swift Symbiodock/App/DebugRender.swift
git commit -m "feat(agents): draw subagents as branches under their session" -m "The owner wants a session's subagents to show like a fork below its row."
git push origin main
```

---

### Task 9: Record the decisions

**Files:**
- Modify: `CLAUDE.md` (decision table, `Durum`, `Yol haritası`)
- Modify: `docs/superpowers/specs/2026-11-14-agents-tab-design.md` (header)

- [ ] **Step 1: Amend the agents spec header**

Below its `Extends:` line add:

```markdown
Amended by: `2026-11-15-subagent-branches-design.md` (subagents as branches, open size
600 × 150, amber question color, scans woken by session file changes).
```

- [ ] **Step 2: Update `CLAUDE.md`**

In the decision table:
- `Agent ilgi belirteci` row: replace `kırmızı #FF4D4F halka` with `amber #FFD60A halka`, and append to its reason: `; 2026-11-15 kırmızıdan ambere: "kırmızı olmasın, sanki fail olmuş gibi duruyor"`.
- `Açık ada genişliği` row: decision `600 × 150 pt; yan kenarda 600 × 170 (2026-11-15; önce 540 × 134)`, reason `Sahibi: "adanın boyunu da uzatalım biraz kısa geldi"`.
- New rows:

```markdown
| Alt ajan dalları | Bir oturumun alt ajanları satırının altında çatal gibi dallanır: `├─`/`└─`, ad ve süre; en fazla 3 satır, fazlası `+N more`. Biten alt ajan, ebeveyn turu bitene kadar soluk ve nane yeşili `Done ✓` ile kalır. Claude Code: `subagents/agent-*.meta.json` (`finished`), durdurulan için ebeveyn transcript'indeki bildirim; Codex: `thread_spawn` rollout'ları. Kapalı adada gösterge yok (2026-11-15) | Sahibi: "subagent filan çalışıyorsa fork gibi gözüksün alt kısmında" (spec: `2026-11-15-subagent-branches-design.md`) |
| Anında temizleme | `~/.claude/sessions` FSEvents ile izlenir, değişince tarama hemen başlar (en sık 0,25 sn'de bir) (2026-11-15) | Sahibi: "soruya cevap verdikten 1 2 sn sonra soru efekti gidiyor"; ölçüm: Claude Code durumu 0,1 sn'de yazıyor, ada 3 sn'de bir bakıyordu |
```

In `Yol haritası`, after Faz 7:

```markdown
- [x] **Faz 8 — Alt ajan dalları, büyük ada, amber soru, anında temizleme.** Kod tamam, elle
      kontrol bekliyor. Spec: `docs/superpowers/specs/2026-11-15-subagent-branches-design.md`.
      Plan: `docs/superpowers/plans/2026-11-15-subagent-branches.md` (elle kontrol listesi sonunda).
```

In `Durum`, add a bullet: `**Faz 8: kod tamam ve main'de (2026-11-15).** <N> çekirdek testi geçiyor. Canlı görülenler: <what Task 3 Step 9 and Task 6 Step 4 showed>. Elle kontrol listesi plan dosyasının sonunda.` (fill `<N>` from the last `swift test` run and the observations from the task reports; leave no angle brackets in the file).

- [ ] **Step 3: Commit and push**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-11-14-agents-tab-design.md
git commit -m "docs: record subagent branches, the larger island and amber" -m "Keeps the decision log and the agents spec in step with what the owner chose on 2026-11-15."
git push origin main
```

---

### Task 10: A colour for each branch

Added on 2026-11-15 at the owner's request ("her bir forka farklı renkler de verelim"); spec 6.2, last bullet.

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentBranches.swift`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentBranchesTests.swift`
- Modify: `Symbiodock/Island/Agents/AgentsContent.swift` (`AgentRowView.block`, `AgentBranchLines`, `Connector`)

**Interfaces:**
- Consumes: `AgentBranch`, `AgentBranches.lines` (Task 4); `AgentPalette.tint(for:strength:across:)` (exists).
- Produces: `AgentBranches.tone(of: String, count: Int) -> Int`, `AgentBranches.tones(for: [AgentBranch], count: Int) -> [Int?]`.

- [ ] **Step 1: Write the failing tests**

Append inside `AgentBranchesTests`:

```swift
    @Test func aToneIsTheSameInEveryRun() {
        // FNV-1a, not `hashValue`, which changes from one launch to the next.
        #expect(AgentBranches.tone(of: "a", count: 3) == 1)
        #expect(AgentBranches.tone(of: "c", count: 3) == 0)
        #expect(AgentBranches.tone(of: "x", count: 3) == 2)
        #expect(AgentBranches.tone(of: "anything", count: 1) == 0)
    }

    @Test func linesNeverShareATone() {
        // "a" and "b" both hash to tone 1; "b" passes to the next free one.
        let lines = [AgentBranch.subagent(sub("a", at: 1)), .subagent(sub("b", at: 2)), .subagent(sub("c", at: 3))]
        #expect(AgentBranches.tones(for: lines, count: 3) == [1, 2, 0])
    }

    @Test func aSubagentKeepsItsToneWhenOthersJoinBelow() {
        let a = AgentBranch.subagent(sub("a", at: 1))
        #expect(AgentBranches.tones(for: [a], count: 3) == [1])
        #expect(AgentBranches.tones(for: [a, .subagent(sub("x", at: 2))], count: 3) == [1, 2])
    }

    @Test func theCountLineHasNoTone() {
        let lines = [AgentBranch.subagent(sub("c", at: 1)), .more(4)]
        #expect(AgentBranches.tones(for: lines, count: 3) == [0, nil])
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter AgentBranchesTests`
Expected: FAIL to compile, `type 'AgentBranches' has no member 'tone'`.

- [ ] **Step 3: Add the tones**

Inside `enum AgentBranches`:

```swift
    /// A subagent's own tone among `count`, from its id: FNV-1a, so the same in every run.
    public static func tone(of id: String, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    /// The tone of each line's dot. A subagent takes its own tone unless a line above has
    /// it; then the next free one, so that up to `count` lines never share a colour. The
    /// count line has none.
    public static func tones(for lines: [AgentBranch], count: Int) -> [Int?] {
        guard count > 0 else { return lines.map { _ in nil } }
        var taken = Set<Int>()
        return lines.map { line in
            guard case .subagent(let subagent) = line else { return nil }
            var pick = Self.tone(of: subagent.id, count: count)
            if taken.count < count {
                while taken.contains(pick) { pick = (pick + 1) % count }
            }
            taken.insert(pick)
            return pick
        }
    }
```

- [ ] **Step 4: Run the core tests**

Run: `swift test --package-path Packages/SymbiodockCore`
Expected: PASS.

- [ ] **Step 5: Colour the ticks and dots**

In `AgentsContent.swift`:

`AgentRowView.block` passes the tool:

```swift
            if !row.branches.isEmpty {
                AgentBranchLines(branches: row.branches, tool: row.session.tool, now: now)
            }
```

In `AgentBranchLines`, add below `trailingInset`:

```swift
    /// The parent pet's colours the dots take: its first, middle and last.
    private static let toneCount = 3
    private static let dotSize: CGFloat = 4
```

add `let tool: AgentTool` between `branches` and `now`, and replace `body` and `line(_:isLast:)` with:

```swift
    var body: some View {
        let tones = AgentBranches.tones(for: branches, count: Self.toneCount)
        VStack(spacing: 0) {
            ForEach(Array(zip(branches, tones)), id: \.0.id) { branch, tone in
                line(branch, tone: tone, isLast: branch.id == branches.last?.id)
            }
        }
        .padding(.bottom, Self.bottomPadding)
    }

    private func line(_ branch: AgentBranch, tone: Int?, isLast: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Connector(x: Self.connectorX, isLast: isLast)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
                Tick(x: Self.connectorX, length: Self.tick)
                    .stroke(tickColor(branch, tone: tone), lineWidth: 1)
                if let tone, case .subagent(let subagent) = branch {
                    Circle()
                        .fill(tint(tone, finished: subagent.isFinished))
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .position(x: Self.connectorX + Self.tick, y: Self.lineHeight / 2)
                }
            }
            .frame(width: Self.connectorX + Self.tick + Self.dotSize / 2, height: Self.lineHeight)
            label(branch)
        }
        .padding(.trailing, Self.trailingInset)
        .frame(height: Self.lineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentLabels.branchDescription(branch, now: now))
    }

    /// A tone of the parent pet's colours; dimmer once the subagent is done.
    private func tint(_ tone: Int, finished: Bool) -> Color {
        let position = Double(tone) / Double(Self.toneCount - 1)
        return AgentPalette.tint(for: tool, across: position).opacity(finished ? 0.45 : 0.9)
    }

    private func tickColor(_ branch: AgentBranch, tone: Int?) -> Color {
        guard let tone, case .subagent(let subagent) = branch else { return .white.opacity(0.22) }
        return tint(tone, finished: subagent.isFinished)
    }
```

`Connector` loses its tick and a `Tick` shape joins it:

```swift
/// The vertical under the pet: on through a line with more below it, ending at the last
/// line's middle (`└`).
private struct Connector: Shape {
    let x: CGFloat
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: isLast ? rect.midY : rect.maxY))
        return path
    }
}

/// The short line from the vertical into a branch (`─`).
private struct Tick: Shape {
    let x: CGFloat
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.midY))
        path.addLine(to: CGPoint(x: x + length, y: rect.midY))
        return path
    }
}
```

- [ ] **Step 6: Build, render, look**

Run the build command and the render command (Task 1 Step 6). Read `build/render/expanded-agents.png` (Claude: three dots in peach, orange and brick, the done one dimmer) and `build/render/expanded-agents-branches.png` (Codex: two blue-to-purple dots, `+2 more` with a white tick and no dot). Names stay white; nothing else in the island changes.

- [ ] **Step 7: Commit and push**

```bash
git add Packages/SymbiodockCore Symbiodock/Island/Agents/AgentsContent.swift
git commit -m "feat(agents): give each subagent branch a tone of its pet's colours" -m "The owner wanted each fork in its own colour; tones of the parent pet keep them tied to their session and clear of amber and mint."
git push origin main
```

---

## Hand checklist (owner)

1. Hover the island at the notch: it opens at 600 × 150 and closes cleanly; no flicker at its edges.
2. Dock it to the left or right edge and hover: it opens at 600 × 170 from the strip and does not flicker.
3. Media tab at the new size: cover, title, progress and controls sit well.
4. Ask Claude Code a question: the collapsed island shows the amber knock and rim light; nothing is red.
5. The Agents tab row of that session has an amber bar, amber background and amber `Needs input`.
6. The tab strip's dot is amber while a question is open.
7. Answer the question: the amber look is gone in about a third of a second.
8. Start two background subagents in a Claude Code session: two branches under its row, `├─` then `└─`, each with its name and time.
9. Let one finish: while the session still works, or when it was idle and wakes up to read the
   result, the branch turns dim with a mint `Done ✓` below the working ones.
10. Let the session finish its turn: the finished branches go.
11. Stop a running subagent: its branch goes within a few seconds.
12. Start four or more subagents: two branches and `+N more`.
13. A session with branches fills the list; scroll down: the list comes to rest on the next session.
14. Click a branch line: the session's app comes forward, as a click on the row does.
15. If Codex is used with subagents: branches with names like `notch market research`.
16. CPU with the island at rest and an agent working: `top` shows about 0 %.
17. Each branch has its own dot colour from its session's pet (Claude: peach, orange, brick); a subagent keeps its colour while it runs; the done one is dimmer.
18. Drag the island off the notch and let its strands catch an edge, then let go: a firm tick on catching and another on sticking; a free release also ticks.
