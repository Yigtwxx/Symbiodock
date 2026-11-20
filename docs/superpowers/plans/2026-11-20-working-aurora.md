# Working Aurora Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While an agent works, the collapsed island shows a flowing light under its free long edge, livelier pets, a coloured working arc and one orbiting dot per working sub-agent.

**Architecture:** Pure decisions and motion formulas live in `Packages/SymbiodockCore` and are tested with `swift test`. The app draws them: live with Core Animation layers (the render server plays them, the app does no work per frame), still with SwiftUI for offscreen renders and Reduce Motion. The light is a separate layer behind the island, because the island clips its own content.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Core Animation, Swift Testing, XcodeGen.

Spec: `docs/superpowers/specs/2026-11-20-working-aurora-design.md`. Read it first.

## Global Constraints

- Minimum macOS 14.0. Swift 6 strict concurrency: views and layers are main-actor.
- No view may redraw frame by frame at rest. Every motion that repeats is a Core Animation layer animation (see the comment at the top of `Symbiodock/Island/LayerAnimation.swift`).
- Do not change `RimLight.swift`, `RimPass.swift`, `CompactingRim.swift` or `TrackGlowLine.swift`.
- Interface text is English. Code, identifiers and comments are English.
- No new third-party dependency.
- Plans are written without compiling. If code here does not compile, fix it while keeping the behaviour and the interfaces, and correct this plan in the same commit.
- Verification after every task:
  - `swift test --package-path Packages/SymbiodockCore` passes (718 tests before this plan).
  - `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3` ends with `** BUILD SUCCEEDED **`.
- Offscreen renders: `SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock` writes PNG files and quits.
- Commits: Conventional Commits, title at most 72 characters, imperative, body says why. Commit each task and push to `main` (`git push origin main`). End every commit message with:

```
Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BW1DAEbG4PxRF2VfV7WUtr
```

## File Structure

| File | Responsibility |
|---|---|
| `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift` (modify) | `showsWorkingAurora` |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/WorkingAurora.swift` (create) | The light's measures, edge choice, band rectangle, breath and flow formulas |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSatellites.swift` (create) | Which sub-agents orbit, their period, phase and tone |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSessionBoard.swift` (modify) | `AgentRow.orbiters` |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentPetFigure.swift` (modify) | Livelier pet measures |
| `Symbiodock/Island/Agents/AgentPalette.swift` (modify) | Livelier pet colours, `aurora(for:)` |
| `Symbiodock/Island/WorkingAuroraLight.swift` (create) | The light: live layers and still drawing |
| `Symbiodock/Island/IslandView.swift` (modify) | Places the light behind the island |
| `Symbiodock/Island/LayerAnimation.swift` (modify) | `SpinningArc` can show a gradient |
| `Symbiodock/Island/Agents/AgentStatusMark.swift` (modify) | Coloured arc, satellites overlay |
| `Symbiodock/Island/Agents/MarkSatellites.swift` (create) | The orbiting dots |
| `Symbiodock/Island/Agents/AgentFaces.swift`, `AgentsContent.swift` (modify) | Pass the tool and the orbiters to the mark |
| `Symbiodock/App/DebugRender.swift` (modify) | `working-aurora.png`, updated galleries |
| `CLAUDE.md` (modify) | Decision record and status |

---

### Task 1: When the light shows

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift` (next to `showsCompactingRim`, about line 414)
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandStateTests.swift` (next to the compacting rim tests, about line 355; the helpers `agent(_:_:)` and `track(playing:)` are already there)

**Interfaces:**
- Consumes: `IslandState.phase`, `.face`, `.board` (`AgentSessionBoard.lead`, `.attention`), all existing.
- Produces: `IslandState.showsWorkingAurora: Bool`.

- [ ] **Step 1: Write the failing tests**

Add after `theMediaFaceShowsNoCompactingRim` in `IslandStateTests.swift`:

```swift
    @Test func theWorkingAuroraShowsWhileTheAgentsFaceWorks() {
        let state = IslandState()
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.showsWorkingAurora)
        state.setHovering(true)
        #expect(!state.showsWorkingAurora)
        state.setHovering(false)
        #expect(state.showsWorkingAurora)
    }

    @Test func theWorkingAuroraIsOnlyForWork() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .compacting)])
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .running)])
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.showsWorkingAurora)
        // It has finished: the seal plays, not the light.
        state.setAgentSessions([agent("a", .idle)])
        #expect(!state.showsWorkingAurora)
    }

    @Test func theWorkingAuroraWaitsBehindAFinishAndAQuestion() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working), agent("b", .working)])
        state.setAgentSessions([agent("a", .idle), agent("b", .working)])
        #expect(!state.showsWorkingAurora)
        state.settleFinished("a")
        #expect(state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .idle), agent("b", .working), agent("c", .needsInput(prompt: nil))])
        #expect(!state.showsWorkingAurora)
    }

    @Test func theMediaFaceShowsNoWorkingAurora() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        #expect(state.face == .media)
        #expect(!state.showsWorkingAurora)
    }
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter IslandStateTests 2>&1 | tail -5`
Expected: a compile error, `value of type 'IslandState' has no member 'showsWorkingAurora'`.

- [ ] **Step 3: Implement**

In `IslandState.swift`, directly after the `showsCompactingRim` property:

```swift
    /// Whether the light of a working agent plays beside the collapsed island: the session
    /// the agents face speaks for is working, and no session asks for attention.
    public var showsWorkingAurora: Bool {
        phase == .collapsed && face == .agents && board.lead?.state == .working
            && board.attention == .none
    }
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -2`
Expected: `Test run with 722 tests in 52 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): decide when a working agent's light shows" -m "The light belongs to the agents face of a collapsed island and stands back for a question, a finish and a compaction, which have lights of their own."
git push origin main
```

(Add the two attribution lines from Global Constraints to every commit body.)

---

### Task 2: The light's measures and motion

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/WorkingAurora.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/WorkingAuroraTests.swift` (create)

**Interfaces:**
- Consumes: `ScreenEdge` (`.top, .bottom, .left, .right`), `IslandLayout.dockedEdges(anchor:)`, `IslandLayout.isSideDocked(_:)`, `IslandAnchor`.
- Produces (all `public static` on `enum WorkingAurora`):
  - `flowPeriod: TimeInterval` (3.2), `breathPeriod: TimeInterval` (2.4), `fade: TimeInterval` (0.35)
  - `reach: CGFloat` (9), `lineWidth: CGFloat` (1), `lineInset: CGFloat` (9), `glowInset: CGFloat` (8), `endFade: CGFloat` (14), `depth: CGFloat` (`reach × longestStretch`)
  - `dimmestGlow` (0.6), `shortestStretch` (0.75), `longestStretch` (1.3), `stillGlow` (0.8), all `Double`
  - `edge(dockedEdges: Set<ScreenEdge>, isVertical: Bool) -> ScreenEdge`
  - `band(island: CGRect, edge: ScreenEdge) -> CGRect`
  - `breath(at:) -> Double`, `glowOpacity(at:) -> Double`, `stretch(at:) -> Double`, `flow(at:) -> Double`, each taking a `TimeInterval`

- [ ] **Step 1: Write the failing tests**

Create `WorkingAuroraTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import SymbiodockCore

struct WorkingAuroraTests {
    private func edge(_ anchor: IslandAnchor) -> ScreenEdge {
        WorkingAurora.edge(
            dockedEdges: IslandLayout.dockedEdges(anchor: anchor),
            isVertical: IslandLayout.isSideDocked(anchor))
    }

    @Test func theLightPlaysAlongTheFreeLongEdge() {
        #expect(edge(.notch) == .bottom)
        #expect(edge(.edge(.top, fraction: 0.3)) == .bottom)
        #expect(edge(.edge(.bottom, fraction: 0.3)) == .top)
        #expect(edge(.edge(.left, fraction: 0.5)) == .right)
        #expect(edge(.edge(.right, fraction: 0.5)) == .left)
        #expect(edge(.corner(.topLeft)) == .bottom)
        #expect(edge(.corner(.topRight)) == .bottom)
        #expect(edge(.corner(.bottomLeft)) == .top)
        #expect(edge(.corner(.bottomRight)) == .top)
    }

    @Test func theBandLiesJustOutsideTheEdge() {
        let island = CGRect(x: 100, y: 0, width: 272, height: 34)
        let depth = WorkingAurora.depth
        #expect(abs(depth - 11.7) < 0.0001)
        #expect(WorkingAurora.band(island: island, edge: .bottom) == CGRect(x: 100, y: 34, width: 272, height: depth))
        #expect(WorkingAurora.band(island: island, edge: .top) == CGRect(x: 100, y: -depth, width: 272, height: depth))
        #expect(WorkingAurora.band(island: island, edge: .left) == CGRect(x: 100 - depth, y: 0, width: depth, height: 34))
        #expect(WorkingAurora.band(island: island, edge: .right) == CGRect(x: 372, y: 0, width: depth, height: 34))
    }

    @Test func theGlowBreathesBetweenItsBounds() {
        #expect(WorkingAurora.breath(at: 0) == 0)
        #expect(abs(WorkingAurora.breath(at: WorkingAurora.breathPeriod / 2) - 1) < 1e-9)
        #expect(abs(WorkingAurora.breath(at: WorkingAurora.breathPeriod)) < 1e-9)
        #expect(abs(WorkingAurora.glowOpacity(at: 0) - 0.6) < 1e-9)
        #expect(abs(WorkingAurora.glowOpacity(at: 1.2) - 1) < 1e-9)
        #expect(abs(WorkingAurora.stretch(at: 0) - 0.75) < 1e-9)
        #expect(abs(WorkingAurora.stretch(at: 1.2) - 1.3) < 1e-9)
        for step in 0...240 {
            let time = Double(step) / 50
            #expect((0.6...1).contains(WorkingAurora.glowOpacity(at: time)))
            #expect((0.75...1.3).contains(WorkingAurora.stretch(at: time)))
        }
    }

    @Test func theColoursTravelOneRunInAPeriod() {
        #expect(WorkingAurora.flow(at: 0) == 0)
        #expect(abs(WorkingAurora.flow(at: 1.6) - 0.5) < 1e-9)
        #expect(abs(WorkingAurora.flow(at: 3.2 + 0.8) - 0.25) < 1e-9)
        #expect(abs(WorkingAurora.flow(at: -0.8) - 0.75) < 1e-9)
    }

    @Test func theMeasuresMatchTheSpec() {
        #expect(WorkingAurora.flowPeriod == 3.2)
        #expect(WorkingAurora.breathPeriod == 2.4)
        #expect(WorkingAurora.reach == 9)
        #expect(WorkingAurora.lineWidth == 1)
        #expect(WorkingAurora.lineInset == 9)
        #expect(WorkingAurora.glowInset == 8)
        #expect(WorkingAurora.stillGlow == 0.8)
        #expect(WorkingAurora.fade == 0.35)
    }
}
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter WorkingAuroraTests 2>&1 | tail -5`
Expected: a compile error, `cannot find 'WorkingAurora' in scope`.

- [ ] **Step 3: Implement**

Create `WorkingAurora.swift`:

```swift
import CoreGraphics
import Foundation

/// The light of a working agent: colours that flow just outside the collapsed island, along
/// its long edge that is free of the screen, as a fine line and a glow that breathes.
/// Measures and motion only, as pure functions; the app draws them.
public enum WorkingAurora {
    /// Seconds the colours take to travel one whole run along the edge.
    public static let flowPeriod: TimeInterval = 3.2
    /// Seconds for one breath of the glow, out and back.
    public static let breathPeriod: TimeInterval = 2.4
    /// Seconds the light takes to appear and to go.
    public static let fade: TimeInterval = 0.35

    /// How far the glow reaches out from the edge at a stretch of 1, in points.
    public static let reach: CGFloat = 9
    public static let lineWidth: CGFloat = 1
    /// How far inside each end of the edge the line begins: clear of the rounded corners.
    public static let lineInset: CGFloat = 9
    /// How far inside each end of the edge the glow begins.
    public static let glowInset: CGFloat = 8
    /// The length at each end over which the line and the glow fade in.
    public static let endFade: CGFloat = 14

    /// The glow's strength at the low point of its breath; at the high point it is 1.
    public static let dimmestGlow = 0.6
    /// How far the glow reaches at the low and at the high point of its breath, as a share
    /// of `reach`.
    public static let shortestStretch = 0.75
    public static let longestStretch = 1.3
    /// The glow's strength when nothing moves (Reduce Motion), at a stretch of 1.
    public static let stillGlow = 0.8

    /// How deep the band beside the edge is: room for the glow at its longest.
    public static var depth: CGFloat { reach * CGFloat(longestStretch) }

    /// The edge of the island the light plays along: its long edge that does not lie
    /// against the screen. A vertical strip is long on its sides, anything else on its top
    /// and bottom.
    public static func edge(dockedEdges: Set<ScreenEdge>, isVertical: Bool) -> ScreenEdge {
        if isVertical { return dockedEdges.contains(.left) ? .right : .left }
        return dockedEdges.contains(.bottom) ? .top : .bottom
    }

    /// The band the light is drawn in: against `edge` of `island`, outside it, as long as
    /// the edge and `depth` deep. Same coordinates as `island` (y runs down).
    public static func band(island: CGRect, edge: ScreenEdge) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: island.minX, y: island.maxY, width: island.width, height: depth)
        case .top: CGRect(x: island.minX, y: island.minY - depth, width: island.width, height: depth)
        case .left: CGRect(x: island.minX - depth, y: island.minY, width: depth, height: island.height)
        case .right: CGRect(x: island.maxX, y: island.minY, width: depth, height: island.height)
        }
    }

    /// How far through its breath the glow is at `time`: 0 at its dimmest and shortest, 1 at
    /// its brightest and longest, easing in and out.
    public static func breath(at time: TimeInterval) -> Double {
        0.5 - 0.5 * cos(2 * .pi * time / breathPeriod)
    }

    /// The glow's strength at `time`, `dimmestGlow`...1.
    public static func glowOpacity(at time: TimeInterval) -> Double {
        dimmestGlow + (1 - dimmestGlow) * breath(at: time)
    }

    /// How far the glow reaches at `time`, as a share of `reach`.
    public static func stretch(at time: TimeInterval) -> Double {
        shortestStretch + (longestStretch - shortestStretch) * breath(at: time)
    }

    /// How far the colours have travelled along the edge at `time`: a share of one run, 0..<1.
    public static func flow(at time: TimeInterval) -> Double {
        let turn = (time / flowPeriod).truncatingRemainder(dividingBy: 1)
        return turn < 0 ? turn + 1 : turn
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -2`
Expected: `Test run with 727 tests in 53 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): measure and time a working agent's light" -m "Where the light lies and how it breathes are pure functions, so the layers and the still renders draw the same thing and both can be tested without the app."
git push origin main
```

---

### Task 3: Which sub-agents orbit

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSatellites.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentSessionBoard.swift` (`AgentRow`, about line 34; `rebuild(from:)`, about line 157)
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentSatellitesTests.swift` (create)

**Interfaces:**
- Consumes: `AgentSubagent(id:title:isFinished:since:)`, `AgentRowState`, `AgentBranches.tone(of:count:)` (a stable hash of an id into `0..<count`).
- Produces:
  - `struct AgentSatellite: Identifiable, Equatable, Sendable { id: String; period: TimeInterval; phase: Double; tone: Int }`
  - `enum AgentSatellites`: `maximum` (5), `periodRange` (`2.3...4.3`), `toneCount` (4), `orbiters(for: [AgentSubagent], state: AgentRowState) -> [AgentSatellite]`, `period(of: String) -> TimeInterval`, `phase(of: String) -> Double`, `turn(of: AgentSatellite, at: TimeInterval) -> Double`, `stillTurn(index: Int, count: Int) -> Double`
  - `AgentRow.orbiters: [AgentSatellite]`

- [ ] **Step 1: Write the failing tests**

Create `AgentSatellitesTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct AgentSatellitesTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func sub(_ id: String, finished: Bool = false, at offset: TimeInterval) -> AgentSubagent {
        AgentSubagent(id: id, title: id, isFinished: finished, since: base.addingTimeInterval(offset))
    }

    @Test func onlyWorkingSubagentsOrbitOldestFirst() {
        let orbiters = AgentSatellites.orbiters(
            for: [sub("new", at: 20), sub("done", finished: true, at: 1), sub("old", at: 5)],
            state: .working)
        #expect(orbiters.map(\.id) == ["old", "new"])
    }

    @Test func nothingOrbitsUnlessTheSessionWorks() {
        let subagents = [sub("a", at: 1)]
        #expect(AgentSatellites.orbiters(for: subagents, state: .needsInput(prompt: nil)).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .compacting).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .finished).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .running).isEmpty)
        #expect(AgentSatellites.orbiters(for: subagents, state: .idle).isEmpty)
    }

    @Test func atMostFiveOrbit() {
        let seven = (1...7).map { sub("s\($0)", at: TimeInterval($0)) }
        let orbiters = AgentSatellites.orbiters(for: seven, state: .working)
        #expect(orbiters.map(\.id) == ["s1", "s2", "s3", "s4", "s5"])
    }

    @Test func aSubagentKeepsItsPeriodAndPhase() {
        let alone = AgentSatellites.orbiters(for: [sub("x", at: 1)], state: .working)[0]
        let among = AgentSatellites.orbiters(for: [sub("w", at: 0), sub("x", at: 9)], state: .working)[1]
        #expect(alone.period == among.period)
        #expect(alone.phase == among.phase)
        #expect(alone.period == AgentSatellites.period(of: "x"))
        #expect(alone.phase == AgentSatellites.phase(of: "x"))
    }

    @Test func periodsAndPhasesStayInRangeAndDiffer() {
        let ids = (0..<200).map { "agent-\($0)" }
        for id in ids {
            #expect(AgentSatellites.periodRange.contains(AgentSatellites.period(of: id)))
            #expect((0..<1).contains(AgentSatellites.phase(of: id)))
        }
        #expect(Set(ids.map { AgentSatellites.period(of: $0) }).count > 100)
        #expect(Set(ids.map { AgentSatellites.phase(of: $0) }).count > 100)
    }

    @Test func satellitesShownTogetherHaveDifferentTones() {
        let four = (1...4).map { sub("s\($0)", at: TimeInterval($0)) }
        let tones = AgentSatellites.orbiters(for: four, state: .working).map(\.tone)
        #expect(Set(tones) == [0, 1, 2, 3])
        // A fifth has to share one.
        let five = (1...5).map { sub("s\($0)", at: TimeInterval($0)) }
        let all = AgentSatellites.orbiters(for: five, state: .working).map(\.tone)
        #expect(all.allSatisfy { (0..<AgentSatellites.toneCount).contains($0) })
        // Alone, a satellite has the tone of its own id.
        let alone = AgentSatellites.orbiters(for: [sub("s3", at: 1)], state: .working)[0]
        #expect(alone.tone == AgentBranches.tone(of: "s3", count: AgentSatellites.toneCount))
    }

    @Test func aSatelliteTurnsOnceInItsPeriod() {
        let satellite = AgentSatellite(id: "x", period: 3, phase: 0.25, tone: 0)
        #expect(abs(AgentSatellites.turn(of: satellite, at: 0) - 0.25) < 1e-9)
        #expect(abs(AgentSatellites.turn(of: satellite, at: 1.5) - 0.75) < 1e-9)
        #expect(abs(AgentSatellites.turn(of: satellite, at: 3) - 0.25) < 1e-9)
        #expect(abs(AgentSatellites.turn(of: satellite, at: -0.75) - 0) < 1e-9)
    }

    @Test func stillSatellitesStandEvenlyApart() {
        #expect(AgentSatellites.stillTurn(index: 0, count: 4) == 0)
        #expect(AgentSatellites.stillTurn(index: 1, count: 4) == 0.25)
        #expect(AgentSatellites.stillTurn(index: 3, count: 4) == 0.75)
        #expect(AgentSatellites.stillTurn(index: 0, count: 0) == 0)
    }

    @Test func aRowCarriesItsOrbiters() {
        var session = AgentSession(
            id: "a", tool: .claudeCode, title: "t", projectPath: nil, activity: .working, since: base, pid: nil)
        session.subagents = [sub("one", at: 1), sub("gone", finished: true, at: 2)]
        var board = AgentSessionBoard()
        board.update([session])
        #expect(board.rows[0].orbiters.map(\.id) == ["one"])
    }
}
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter AgentSatellitesTests 2>&1 | tail -5`
Expected: a compile error, `cannot find 'AgentSatellites' in scope`.

- [ ] **Step 3: Implement the satellites**

Create `AgentSatellites.swift`:

```swift
import Foundation

/// One working sub-agent as it circles the working mark of a collapsed face.
public struct AgentSatellite: Identifiable, Equatable, Sendable {
    /// The sub-agent's id.
    public let id: String
    /// Seconds for one turn round the mark.
    public let period: TimeInterval
    /// Where on the circle it is at time 0: a share of a turn, 0..<1, clockwise from the top.
    public let phase: Double
    /// Which of its tool's light colours it has, `0..<AgentSatellites.toneCount`.
    public let tone: Int

    public init(id: String, period: TimeInterval, phase: Double, tone: Int) {
        self.id = id
        self.period = period
        self.phase = phase
        self.tone = tone
    }
}

/// Which sub-agents circle a session's working mark, and how.
public enum AgentSatellites {
    /// The most satellites round one mark; further sub-agents are not shown.
    public static let maximum = 5
    /// Seconds for one turn: each satellite has its own, so they never move as one.
    public static let periodRange: ClosedRange<TimeInterval> = 2.3...4.3
    /// How many light colours a tool has to give.
    public static let toneCount = 4

    /// The working sub-agents of a session that works: oldest first, at most `maximum`.
    /// A session that waits, compacts, has finished or idles has none.
    public static func orbiters(for subagents: [AgentSubagent], state: AgentRowState) -> [AgentSatellite] {
        guard state == .working else { return [] }
        var taken = Set<Int>()
        return subagents
            .filter { !$0.isFinished }
            .sorted { ($0.since, $0.id) < ($1.since, $1.id) }
            .prefix(maximum)
            .map { subagent in
                // Its own tone unless one shown before it has it; then the next free one.
                var tone = AgentBranches.tone(of: subagent.id, count: toneCount)
                if taken.count < toneCount {
                    while taken.contains(tone) { tone = (tone + 1) % toneCount }
                }
                taken.insert(tone)
                return AgentSatellite(
                    id: subagent.id, period: period(of: subagent.id), phase: phase(of: subagent.id), tone: tone)
            }
    }

    /// A sub-agent's time for one turn, from its id: the same in every run.
    public static func period(of id: String) -> TimeInterval {
        periodRange.lowerBound + (periodRange.upperBound - periodRange.lowerBound) * share(of: id, salt: "period")
    }

    /// Where a sub-agent starts on its circle, from its id: 0..<1 of a turn.
    public static func phase(of id: String) -> Double {
        share(of: id, salt: "phase") * 0.9999
    }

    /// Where `satellite` is at `time`: a share of a turn, 0..<1, clockwise from the top.
    public static func turn(of satellite: AgentSatellite, at time: TimeInterval) -> Double {
        let turn = (satellite.phase + time / satellite.period).truncatingRemainder(dividingBy: 1)
        return turn < 0 ? turn + 1 : turn
    }

    /// Where satellite `index` of `count` stands when nothing moves: evenly round the circle.
    public static func stillTurn(index: Int, count: Int) -> Double {
        count > 0 ? Double(index) / Double(count) : 0
    }

    /// A number 0...1 from an id and a salt: FNV-1a, so the same in every run.
    private static func share(of id: String, salt: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(salt):\(id)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Double(hash % 10_000) / 9_999
    }
}
```

- [ ] **Step 4: Give the row its orbiters**

In `AgentSessionBoard.swift`, in `struct AgentRow` after `branches`:

```swift
    /// The working sub-agents that circle the row's working mark on a collapsed face.
    public let orbiters: [AgentSatellite]
```

In `rebuild(from:)`, add the argument to the `AgentRow(` call after `branches:`:

```swift
                    branches: AgentBranches.lines(
                        for: session.subagents, state: state, turnStart: turnStarts[session.id]),
                    orbiters: AgentSatellites.orbiters(for: session.subagents, state: state))
```

- [ ] **Step 5: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -2`
Expected: `Test run with 736 tests in 54 suites passed`.

- [ ] **Step 6: Correct the spec's line about colour, then commit**

In `docs/superpowers/specs/2026-11-20-working-aurora-design.md`, replace the line that begins `- **Renk.** Aracın dört ışık rengi, sırayla` (in the section "Alt ajan uyduları") with:

```markdown
- **Renk.** Aracın dört ışık renginden biri, alt ajanın kimliğinden; aynı anda görünen uydular
  renk bitene kadar farklı renktedir. Sıraya göre verilseydi biri bitince kalanların rengi
  değişirdi.
```

```bash
git add Packages/SymbiodockCore docs/superpowers/specs/2026-11-20-working-aurora-design.md
git commit -m "feat(core): choose the sub-agents that circle the working mark" -m "Each working sub-agent becomes a satellite with a period and a starting point taken from its id, so it is where it was whenever the face is drawn again."
git push origin main
```

---

### Task 4: Livelier pets

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/Agents/AgentPetFigure.swift` (constants at lines 19-32, `shade(of:x:y:peak:)` at about line 113, `AgentPetMotion.waveRest` at about line 138)
- Modify: `Symbiodock/Island/Agents/AgentPalette.swift` (`run(for:)`)
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AgentPetFigureTests.swift`

**Interfaces:**
- Consumes: `AgentPetFigure.figure(for:) -> AgentPetFigure` with `lines: [[Double]]` (0 where a line shows only the ground, `glowShade` where the figure glows).
- Produces: `AgentPetFigure.shadeLift: Double` (0.62). The other names are unchanged.

- [ ] **Step 1: Render the pets as they are now**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render-before build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
ls build/render-before/pets.png
```

Expected: the file is listed. It is the "before" picture for the owner.

- [ ] **Step 2: Write the failing tests**

Add to `AgentPetFigureTests.swift`, inside the test struct:

```swift
    @Test func shadesAreLiftedTowardsTheFullColour() {
        #expect(AgentPetFigure.shadeLift == 0.62)
        let floor = 1 - (1 - AgentPetFigure.faintestShade) * AgentPetFigure.shadeLift
        #expect(abs(floor - 0.6032) < 0.0001)
        for tool in AgentTool.allCases {
            let shades = AgentPetFigure.figure(for: tool).lines.flatMap { $0 }
                .filter { $0 > 0 && $0 != AgentPetFigure.glowShade }
            #expect(!shades.isEmpty)
            #expect(shades.allSatisfy { $0 >= floor - 1e-9 && $0 <= 1 })
        }
    }

    @Test func thePetsStandOutMore() {
        #expect(AgentPetFigure.groundStrength == 0.12)
        #expect(AgentPetMotion.waveRest == 0.92)
        #expect(abs(AgentPetFigure.barWidth / AgentPetFigure.pitch - 0.68) < 1e-9)
    }
```

- [ ] **Step 3: Run them and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore --filter AgentPetFigureTests 2>&1 | tail -5`
Expected: a compile error, `type 'AgentPetFigure' has no member 'shadeLift'`.

- [ ] **Step 4: Change the measures**

In `AgentPetFigure.swift`:

```swift
    private static let barShare = 0.68
    /// How bright the lines are where there is no figure: the ground it stands out from.
    public static let groundStrength = 0.12
    /// The dimmest the relief can make a part of a figure, before the lift.
    public static let faintestShade = 0.36
    /// How much of its distance from the full colour a shaded part keeps: every shade is
    /// drawn towards the full colour, so the pet shows more of it and its forms still read.
    /// 1 is no lift.
    public static let shadeLift = 0.62
```

(`barShare` was 0.6, `groundStrength` 0.085. Keep the existing comments on the other constants.)

At the end of `shade(of:x:y:peak:)`, replace the `return` line:

```swift
        let shade = min(max(pow((0.52 + 0.48 * facing) * nearness, 0.62), faintestShade), 1)
        return 1 - (1 - shade) * shadeLift
```

In `enum AgentPetMotion`:

```swift
    public static let waveRest = 0.92
```

- [ ] **Step 5: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -2`
Expected: `Test run with 738 tests in 54 suites passed`. If an older test fails because it pinned one of the old values, change its expectation to the new value and say so in the commit body; do not weaken what it checks.

- [ ] **Step 6: Change the colours**

In `AgentPalette.swift`, replace four cases of `run(for:)`:

```swift
        case .claudeCode: [(255, 170, 100), (255, 122, 61), (240, 78, 40)]  // #FFAA64 #FF7A3D #F04E28
        case .codex: [(60, 175, 255), (105, 115, 255), (165, 80, 255)]  // #3CAFFF #6973FF #A550FF
        case .openCode: [(255, 232, 170), (255, 186, 80)]  // #FFE8AA #FFBA50
        case .aider: [(214, 255, 71), (116, 255, 46)]  // #D6FF47 #74FF2E
```

Gemini, Cursor and Copilot stay as they are.

- [ ] **Step 7: Build, render, look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Expected: `** BUILD SUCCEEDED **`. Open `build/render-before/pets.png` and `build/render/pets.png` and compare: every pet is brighter, its eyes and other dark details are still dark, and its forms still read as volume (a lit side, a shaded side). Report both paths. If a pet has gone flat, do not tune it in this task: report it.

- [ ] **Step 8: Commit**

```bash
git add Packages/SymbiodockCore Symbiodock/Island/Agents/AgentPalette.swift
git commit -m "feat(island): make the pets livelier" -m "The owner found the working island dull and chose the livelier of three colour levels from a live mockup: shades are lifted towards the full colour, lines are a little thicker and wait less far back in the wave."
git push origin main
```

---

### Task 5: The light

**Files:**
- Modify: `Symbiodock/Island/Agents/AgentPalette.swift` (add `aurora(for:)`)
- Create: `Symbiodock/Island/WorkingAuroraLight.swift`
- Modify: `Symbiodock/Island/IslandView.swift` (`body`, about line 20; a new `workingAurora` property)
- Modify: `Symbiodock/App/DebugRender.swift` (a `write(` call in `runIfRequested`, a new gallery)

**Interfaces:**
- Consumes: Task 1 `IslandState.showsWorkingAurora`; Task 2 `WorkingAurora` (all members); `SharedClock.begin(in:)` and `CAKeyframeAnimation.repeating(_:period:begin:value:)` from `LayerAnimation.swift`; `IslandLayout.frame(anchor:phase:notch:visibleFrame:screenSize:showsWings:)`, `IslandLayout.dockedEdges(anchor:)`, `IslandLayout.isSideDocked(_:)`.
- Produces: `AgentPalette.aurora(for: AgentTool) -> [Color]` (always four); `struct WorkingAuroraLight: View` with `init(tool: AgentTool, edge: ScreenEdge, frozenAt: TimeInterval? = nil)`.

- [ ] **Step 1: The colours**

In `AgentPalette.swift`, add inside `enum AgentPalette`:

```swift
    /// The four colours of a tool's working light, in the order they follow each other
    /// along the island's edge: the pet's own tones and their neighbours. None is the alert
    /// amber, the finished mint or the compacting purple. The working arc runs from the
    /// first to the second; a sub-agent's satellite has one of the four.
    static func aurora(for tool: AgentTool) -> [Color] {
        let hex: [UInt32] =
            switch tool {
            case .claudeCode: [0xFFB347, 0xFF4D6D, 0xFF7A3D, 0xFFD166]
            case .codex: [0x39C8FF, 0xA259FF, 0x5B7CFF, 0xE05CFF]
            case .geminiCLI: [0x3C87FF, 0xFF78A5, 0x9669FF, 0x5CD0FF]
            case .cursorAgent: [0xFAFAFC, 0xB9C6FF, 0xBEBECC, 0xE6D9FF]
            case .openCode: [0xFFE8AA, 0xFF9F5A, 0xF0AF4B, 0xFFD98A]
            case .aider: [0xD2FA46, 0x39D353, 0x64DC28, 0xF2FF7A]
            case .copilotCLI: [0xA078FF, 0xFF69BE, 0xC86BFF, 0xFF9AD5]
            }
        return hex.map {
            Color(
                red: Double(($0 >> 16) & 0xFF) / 255, green: Double(($0 >> 8) & 0xFF) / 255,
                blue: Double($0 & 0xFF) / 255)
        }
    }
```

- [ ] **Step 2: The view**

Create `Symbiodock/Island/WorkingAuroraLight.swift`:

```swift
import AppKit
import SwiftUI
import SymbiodockCore

/// The light of a working agent (`WorkingAurora`): colours that flow along the island's
/// free long edge, just outside it, as a fine line and a glow that breathes. The view fills
/// the band beside that edge. Live, Core Animation plays it (`AuroraFlow`) and the app does
/// no work per frame (see `LayerAnimation.swift`); still (`frozenAt`, Reduce Motion) SwiftUI
/// draws one moment, once.
struct WorkingAuroraLight: View {
    let tool: AgentTool
    /// The island's edge the band lies against.
    let edge: ScreenEdge
    /// Draws the light as it is this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How strong the glow is on its way out from the edge: `place` runs 0 at the edge to 1
    /// at the end of its reach.
    static let falloff: [(place: Double, strength: Double)] = [(0, 1), (0.3, 0.5), (0.65, 0.15), (1, 0)]

    var body: some View {
        Group {
            if let frozenAt {
                AuroraStill(
                    colors: colors, edge: edge, flow: WorkingAurora.flow(at: frozenAt),
                    glow: WorkingAurora.glowOpacity(at: frozenAt), stretch: WorkingAurora.stretch(at: frozenAt))
            } else if reduceMotion {
                AuroraStill(colors: colors, edge: edge, flow: 0, glow: WorkingAurora.stillGlow, stretch: 1)
            } else {
                AuroraFlow(colors: colors.map { NSColor($0).cgColor }, edge: edge)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var colors: [Color] { AgentPalette.aurora(for: tool) }

    /// The colours as they lie along twice the edge: two whole runs that end where they
    /// began, so that a slide of one edge's length brings them back to the start.
    static func run<C>(_ colors: [C]) -> [C] { colors + colors + [colors[0]] }

    /// Where the line and the glow fade in at their ends, for a piece `length` long:
    /// gradient locations for clear, full, full, clear.
    static func endLocations(length: CGFloat) -> [Double] {
        let fade = length > 0 ? min(Double(WorkingAurora.endFade / length), 0.5) : 0.5
        return [0, fade, 1 - fade, 1]
    }
}

/// One moment of the light, drawn once. It is drawn as if the edge ran along the top with
/// the light going down, and the context is turned to the edge it is for.
private struct AuroraStill: View {
    let colors: [Color]
    let edge: ScreenEdge
    /// How far the colours have travelled, a share of one run.
    let flow: Double
    let glow: Double
    let stretch: Double

    var body: some View {
        Canvas { context, size in
            let isSide = edge == .left || edge == .right
            let length = isSide ? size.height : size.width
            context.concatenate(Self.placing(edge: edge, in: size))
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: WorkingAuroraLight.run(colors)),
                startPoint: CGPoint(x: (flow - 1) * length, y: 0),
                endPoint: CGPoint(x: (flow + 1) * length, y: 0))
            let glowRect = CGRect(
                x: WorkingAurora.glowInset, y: 0, width: length - 2 * WorkingAurora.glowInset,
                height: WorkingAurora.reach * stretch)
            draw(shading, in: glowRect, fallsOff: true, opacity: glow, context: context)
            let lineRect = CGRect(
                x: WorkingAurora.lineInset, y: 0, width: length - 2 * WorkingAurora.lineInset,
                height: WorkingAurora.lineWidth)
            draw(shading, in: lineRect, fallsOff: false, opacity: 1, context: context)
        }
    }

    /// Fills `rect` with the colours, fading in at both ends and, for the glow, fading out
    /// away from the edge.
    private func draw(
        _ shading: GraphicsContext.Shading, in rect: CGRect, fallsOff: Bool, opacity: Double,
        context: GraphicsContext
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        var layer = context
        layer.opacity = opacity
        let ends = WorkingAuroraLight.endLocations(length: rect.width)
        layer.clipToLayer { mask in
            mask.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: ends[0]), .init(color: .white, location: ends[1]),
                        .init(color: .white, location: ends[2]), .init(color: .clear, location: ends[3]),
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        }
        if fallsOff {
            layer.clipToLayer { mask in
                mask.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(stops: WorkingAuroraLight.falloff.map {
                            .init(color: .white.opacity($0.strength), location: $0.place)
                        }),
                        startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            }
        }
        layer.fill(Path(rect), with: shading)
    }

    /// Maps the band as drawn (x along the edge, y out from it, y running down) onto a band
    /// of `size` beside `edge`. The colours run left to right, and top to bottom on a side.
    private static func placing(edge: ScreenEdge, in size: CGSize) -> CGAffineTransform {
        switch edge {
        case .bottom: .identity
        case .top: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        case .left: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0)
        case .right: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }
}

/// The live light. A sheet of the colours, twice the edge long, slides by one edge's length
/// again and again; it shows through a mask of a fine line and a glow, and the glow's
/// strength and reach rise and fall. The render server plays all of it.
private struct AuroraFlow: NSViewRepresentable {
    let colors: [CGColor]
    let edge: ScreenEdge

    func makeNSView(context: Context) -> FlowView { FlowView() }

    func updateNSView(_ view: FlowView, context: Context) {
        view.configure(colors: colors, edge: edge)
    }

    static func dismantleNSView(_ view: FlowView, coordinator: ()) {
        view.stop()
    }

    final class FlowView: NSView {
        /// The band as it is laid out: x along the edge, y out from it, y running up as in
        /// every layer. Its transform turns it to the edge it is for.
        private let band = CALayer()
        /// What shows: the colours, through `shape`.
        private let sheet = CALayer()
        private let run = CAGradientLayer()
        private let shape = CALayer()
        private let glow = CAGradientLayer()
        private let glowEnds = CAGradientLayer()
        private let line = CAGradientLayer()
        private var edge: ScreenEdge = .bottom
        /// The edge's length the animations were made for.
        private var playedLength: CGFloat = 0

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            run.startPoint = CGPoint(x: 0, y: 0.5)
            run.endPoint = CGPoint(x: 1, y: 0.5)
            run.anchorPoint = .zero
            // Strongest at the edge (the bottom of the band as laid out), nothing at its reach.
            glow.colors = WorkingAuroraLight.falloff.map { NSColor.white.withAlphaComponent($0.strength).cgColor }
            glow.locations = WorkingAuroraLight.falloff.map { NSNumber(value: $0.place) }
            glow.startPoint = CGPoint(x: 0.5, y: 0)
            glow.endPoint = CGPoint(x: 0.5, y: 1)
            // It stretches away from the edge, which stays where it is.
            glow.anchorPoint = CGPoint(x: 0.5, y: 0)
            for ends in [glowEnds, line] {
                ends.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
                ends.startPoint = CGPoint(x: 0, y: 0.5)
                ends.endPoint = CGPoint(x: 1, y: 0.5)
            }
            glow.mask = glowEnds
            shape.addSublayer(glow)
            shape.addSublayer(line)
            sheet.masksToBounds = true
            sheet.addSublayer(run)
            sheet.mask = shape
            band.addSublayer(sheet)
            layer?.addSublayer(band)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(colors: [CGColor], edge: ScreenEdge) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            run.colors = WorkingAuroraLight.run(colors)
            CATransaction.commit()
            if self.edge != edge {
                self.edge = edge
                needsLayout = true
            }
            play()
        }

        /// Takes the light down: no animation is left.
        func stop() {
            run.removeAllAnimations()
            glow.removeAllAnimations()
            playedLength = 0
        }

        override func layout() {
            super.layout()
            let isSide = edge == .left || edge == .right
            let length = isSide ? bounds.height : bounds.width
            let depth = isSide ? bounds.width : bounds.height
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            band.bounds = CGRect(x: 0, y: 0, width: length, height: depth)
            band.position = CGPoint(x: bounds.midX, y: bounds.midY)
            band.setAffineTransform(Self.turn(to: edge))
            sheet.frame = band.bounds
            shape.frame = band.bounds
            run.bounds = CGRect(x: 0, y: 0, width: 2 * length, height: depth)
            run.position = CGPoint(x: -length, y: 0)
            let glowLength = max(length - 2 * WorkingAurora.glowInset, 0)
            glow.bounds = CGRect(x: 0, y: 0, width: glowLength, height: WorkingAurora.reach)
            glow.position = CGPoint(x: length / 2, y: 0)
            glowEnds.frame = glow.bounds
            glowEnds.locations = WorkingAuroraLight.endLocations(length: glowLength).map { NSNumber(value: $0) }
            let lineLength = max(length - 2 * WorkingAurora.lineInset, 0)
            line.frame = CGRect(
                x: WorkingAurora.lineInset, y: 0, width: lineLength, height: WorkingAurora.lineWidth)
            line.locations = WorkingAuroraLight.endLocations(length: lineLength).map { NSNumber(value: $0) }
            CATransaction.commit()
            play()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Off screen the animations have nothing to show; they are added again on return.
                stop()
            } else {
                play()
            }
        }

        private func play() {
            let length = band.bounds.width
            guard window != nil, length > 0 else { return }
            // The slide is as long as the edge: a new length needs a new slide.
            if playedLength != length {
                playedLength = length
                let slide = CABasicAnimation(keyPath: "position.x")
                slide.fromValue = -length
                slide.toValue = 0
                slide.duration = WorkingAurora.flowPeriod
                slide.repeatCount = .infinity
                slide.timingFunction = CAMediaTimingFunction(name: .linear)
                slide.beginTime = SharedClock.begin(in: run)
                slide.isRemovedOnCompletion = false
                run.add(slide, forKey: "flow")
            }
            guard glow.animation(forKey: "breath") == nil else { return }
            let begin = SharedClock.begin(in: glow)
            glow.add(
                CAKeyframeAnimation.repeating(
                    "opacity", period: WorkingAurora.breathPeriod, begin: begin, value: WorkingAurora.glowOpacity),
                forKey: "breath")
            glow.add(
                CAKeyframeAnimation.repeating(
                    "transform.scale.y", period: WorkingAurora.breathPeriod, begin: begin, value: WorkingAurora.stretch),
                forKey: "stretch")
        }

        /// Turns the band as laid out (edge along its bottom, light going up, colours
        /// running to the right) to `edge`, about its centre. The view's y runs up.
        private static func turn(to edge: ScreenEdge) -> CGAffineTransform {
            switch edge {
            // The island is above the band: the edge is the band's top, the light goes down.
            case .bottom: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            case .top: .identity
            // The island is right of the band: light to the left, colours running down.
            case .left: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 0, ty: 0)
            // The island is left of the band: light to the right, colours running down.
            case .right: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
            }
        }
    }
}
```

- [ ] **Step 3: Put it behind the island**

In `IslandView.swift`, in `body`'s `ZStack`, add one line after `filesBubble`:

```swift
                bubble
                filesBubble
                // Behind the island too: only what lies outside it shows.
                workingAurora
```

Add the property next to `filesBubble`:

```swift
    /// The light of a working agent, in a band just outside the collapsed island's free long
    /// edge. The light shows only while the island is collapsed, so the band is always the
    /// collapsed island's. It is not an overlay of the island, which clips what it holds.
    private var workingAurora: some View {
        let frame = IslandLayout.frame(
            anchor: state.anchor, phase: .collapsed, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
        let edge = WorkingAurora.edge(
            dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor),
            isVertical: IslandLayout.isSideDocked(state.anchor))
        let band = WorkingAurora.band(island: frame, edge: edge)
        return ZStack {
            if state.showsWorkingAurora, let tool = state.board.lead?.session.tool {
                // The edge is its identity: a new edge is a new light, not a stretched one.
                WorkingAuroraLight(tool: tool, edge: edge)
                    .id(edge)
                    .transition(.opacity)
            }
        }
        .frame(width: band.width, height: band.height)
        .offset(x: band.minX, y: band.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Self.spring, value: state.showsWings)
        .animation(Self.spring, value: state.anchor)
        // Last, so outermost: the innermost animation of those whose values change in one
        // update wins, and the fade must win over the springs.
        .animation(.easeInOut(duration: WorkingAurora.fade), value: state.showsWorkingAurora)
    }
```

- [ ] **Step 4: A render to check it**

In `DebugRender.swift`, in `runIfRequested`, after the line that writes `collapsed-faces`:

```swift
        write(WorkingAuroraGallery(), size: CGSize(width: 660, height: 520), named: "working-aurora", to: directory)
```

Add the gallery at the end of the file, before the final `#endif`:

```swift
/// The light of a working agent: at the notch at its dimmest and at its brightest, for a
/// second tool, beside a capsule docked at the bottom and a strip docked right. The last
/// notch is the live layers at rest, to check that they lie the way the drawing does.
private struct WorkingAuroraGallery: View {
    private func row(_ tool: AgentTool) -> AgentRow {
        var board = AgentSessionBoard()
        board.update([
            AgentSession(
                id: "x", tool: tool, title: "fix-login-flow", projectPath: nil,
                activity: .working, since: Date(), pid: nil)
        ])
        return board.rows[0]
    }

    private func island(
        _ anchor: IslandAnchor, _ size: CGSize, tool: AgentTool, at time: TimeInterval?,
        @ViewBuilder face: () -> some View
    ) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)
        let edge = WorkingAurora.edge(
            dockedEdges: IslandLayout.dockedEdges(anchor: anchor), isVertical: IslandLayout.isSideDocked(anchor))
        let margin = WorkingAurora.depth + 4
        let frame = CGRect(x: margin, y: margin, width: size.width, height: size.height)
        let band = WorkingAurora.band(island: frame, edge: edge)
        return ZStack(alignment: .topLeading) {
            WorkingAuroraLight(tool: tool, edge: edge, frozenAt: time)
                .frame(width: band.width, height: band.height)
                .offset(x: band.minX, y: band.minY)
            shape.fill(.black)
                .overlay { face() }
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .offset(x: frame.minX, y: frame.minY)
        }
        .frame(width: size.width + 2 * margin, height: size.height + 2 * margin, alignment: .topLeading)
    }

    private func notch(_ tool: AgentTool, at time: TimeInterval?) -> some View {
        island(.notch, CGSize(width: 272, height: 32 + IslandLayout.notchLip), tool: tool, at: time) {
            AgentNotchFace(row: row(tool), notchWidth: 200)
                .padding(.bottom, IslandLayout.notchLip)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                // Dimmest, brightest, and a quarter of a run on.
                notch(.claudeCode, at: 0)
                notch(.claudeCode, at: WorkingAurora.breathPeriod / 2)
                notch(.claudeCode, at: WorkingAurora.flowPeriod / 4)
                notch(.codex, at: WorkingAurora.breathPeriod / 2)
                island(.edge(.bottom, fraction: 0.5), CGSize(width: 200, height: 36), tool: .codex, at: 1.2) {
                    AgentFloatingFace(row: row(.codex))
                }
                notch(.claudeCode, at: nil)
            }
            island(.edge(.right, fraction: 0.5), CGSize(width: 36, height: 170), tool: .claudeCode, at: 1.2) {
                AgentSideFace(row: row(.claudeCode))
            }
        }
        .padding(16)
    }
}
```

- [ ] **Step 5: Build and render**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Expected: `** BUILD SUCCEEDED **` and `build/render/working-aurora.png`. Open the picture and check each of these:

1. Under each notch there is a fine coloured line just below the island and a soft glow under it that fades downward; nothing is drawn over the black island.
2. The first notch's glow is dimmer and shorter than the second's.
3. The third notch has the same colours shifted to the right by a quarter of the island's width.
4. The Codex notch is blue and purple, the Claude Code ones orange and pink.
5. The capsule docked at the bottom has its light above it, fading upward.
6. The strip docked right has its light on its left side, fading to the left.
7. The last notch (live layers) looks like the second one within the limits of a snapshot: line below the island, glow fading downward. If it is upside down or on the wrong side, `turn(to:)` is wrong for that edge; fix it and say so.

Report what you see for each point.

- [ ] **Step 6: Run it live**

```bash
pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_AGENTS=working build/Build/Products/Debug/Symbiodock.app
sleep 4 && swift scripts/list-windows.swift | head -5
top -l 4 -stats pid,command,cpu -pid $(pgrep -x Symbiodock) | grep Symbiodock
pkill -x Symbiodock
```

Expected: the app is still running after 4 seconds (no crash), and the last three CPU samples are about 0 (below 1.0). The first sample of `top` is not meaningful. Report the numbers. If the CPU stays above 1 %, sample it (`sample Symbiodock 3`) and report what the main thread is doing; do not hide it.

- [ ] **Step 7: Commit**

```bash
git add Symbiodock
git commit -m "feat(island): light the edge of the island while an agent works" -m "The working state was the only one without a light of its own. The light lies just outside the island's free long edge, in a layer behind it, because the island clips what it holds; Core Animation plays it."
git push origin main
```

---

### Task 6: The coloured arc

**Files:**
- Modify: `Symbiodock/Island/LayerAnimation.swift` (`SpinningArc`, lines 47-144)
- Modify: `Symbiodock/Island/Agents/AgentStatusMark.swift`
- Modify: `Symbiodock/Island/Agents/AgentFaces.swift` (three `AgentStatusMark(` calls), `Symbiodock/Island/Agents/AgentsContent.swift` (one call, about line 171)
- Modify: `Symbiodock/App/DebugRender.swift` (`StatusMarkGallery`)

**Interfaces:**
- Consumes: Task 5 `AgentPalette.aurora(for:)`.
- Produces: `SpinningArc.gradient: [Color]?` (nil by default); `AgentStatusMark.tool: AgentTool?` (nil by default). `AgentStatusMark`'s memberwise order becomes `state, size, tool, frozenAt`.

- [ ] **Step 1: Let the spinning arc show a gradient**

In `LayerAnimation.swift`, in `struct SpinningArc`, add a property after `color` and pass it on:

```swift
    let color: Color
    /// Colours the arc shows instead of `color`, from the upper left to the lower right.
    /// They stand still and the arc turns over them, so it changes colour as it goes.
    var gradient: [Color]? = nil
```

```swift
    func updateNSView(_ view: ArcView, context: Context) {
        view.configure(
            color: NSColor(color), gradient: gradient?.map { NSColor($0).cgColor }, lineWidth: lineWidth,
            period: period, sweep: sweep, dashCount: dashCount)
    }
```

In `ArcView`, add two properties:

```swift
        private let tint = CAGradientLayer()
        /// Whether the arc is the mask of `tint` instead of a line of its own.
        private var isTinted = false
```

In `init(frame:)`, after `arc.lineCap = .round`:

```swift
        // The layer's coordinates run upward: the upper left is (0, 1).
        tint.startPoint = CGPoint(x: 0, y: 1)
        tint.endPoint = CGPoint(x: 1, y: 0)
```

Replace `configure` with:

```swift
        func configure(
            color: NSColor, gradient: [CGColor]?, lineWidth: CGFloat, period: TimeInterval, sweep: Double,
            dashCount: Int?
        ) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.lineWidth = lineWidth
            if let gradient {
                // The mask only says where the colours show.
                arc.strokeColor = NSColor.white.cgColor
                tint.colors = gradient
            } else {
                arc.strokeColor = color.cgColor
            }
            if isTinted != (gradient != nil) {
                isTinted = gradient != nil
                arc.removeFromSuperlayer()
                tint.removeFromSuperlayer()
                tint.mask = nil
                if isTinted {
                    tint.mask = arc
                    layer?.addSublayer(tint)
                } else {
                    layer?.addSublayer(arc)
                }
                needsLayout = true
            }
            CATransaction.commit()
            if self.period != period || self.sweep != sweep || self.dashCount != dashCount {
                self.period = period
                self.sweep = sweep
                self.dashCount = dashCount
                needsLayout = true
            }
            startSpinning()
        }
```

In `layout()`, replace the line `arc.frame = bounds` with:

```swift
            // The line reaches half its width past the circle; the colours have to cover it.
            let reach = arc.lineWidth
            tint.frame = bounds.insetBy(dx: -reach, dy: -reach)
            arc.frame = isTinted ? CGRect(x: reach, y: reach, width: bounds.width, height: bounds.height) : bounds
```

(The path is still made in `bounds`' size; the arc's own bounds have that size in both cases.)

- [ ] **Step 2: The mark knows its tool**

In `AgentStatusMark.swift`, add a property after `size`:

```swift
    var size: CGFloat = 14
    /// The session's tool. A working mark then turns in the tool's light colours instead of
    /// white.
    var tool: AgentTool?
```

Add, next to `color`:

```swift
    /// The colours a working arc runs through, upper left to lower right; nil for white.
    private var arcColors: [Color]? {
        guard state == .working, let tool else { return nil }
        let light = AgentPalette.aurora(for: tool)
        return [light[0], light[1]]
    }

    /// The ring drawn still, `turn` degrees round. Colours stand still; the arc is their mask.
    @ViewBuilder
    private func ring(turn: Double) -> some View {
        let arc = Circle()
            .trim(from: 0, to: state == .working ? 0.75 : 1)
            .stroke(
                style: StrokeStyle(
                    lineWidth: Self.stroke, lineCap: .round,
                    dash: isCompacting ? [dashLength, dashLength] : []))
            .rotationEffect(.degrees(turn - 90))
        if let arcColors {
            // The line reaches half its width past the circle; the colours are laid wider.
            LinearGradient(colors: arcColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .padding(-Self.stroke)
                .mask { arc.padding(Self.stroke) }
        } else {
            arc.foregroundStyle(color)
        }
    }
```

In `mark`, replace the still ring (the `Circle().trim(...)...rotationEffect(...).opacity(spins ? 0 : 1)` expression) with:

```swift
            ring(turn: turn)
                .opacity(spins ? 0 : 1)
```

and give the live arc its colours:

```swift
                SpinningArc(
                    color: color, gradient: arcColors, lineWidth: Self.stroke, period: period,
                    sweep: isCompacting ? 1 : 0.75,
                    dashCount: isCompacting ? Self.compactDashes : nil)
                    .transition(.opacity)
```

- [ ] **Step 3: Pass the tool**

In `AgentFaces.swift`:

```swift
            AgentStatusMark(state: row.state, tool: row.session.tool)
```

```swift
                AgentStatusMark(state: row.isSettled ? .idle : row.state, tool: row.session.tool)
```

(the second form twice: in `AgentFloatingFace` and in `AgentSideFace`).

In `AgentsContent.swift`:

```swift
            AgentStatusMark(state: row.state, tool: row.session.tool)
                .accessibilityHidden(true)
```

Leave `CollapsedContent.swift`, `SideCollapsedContent.swift` and `FloatingCollapsedContent.swift` alone: their marks show a question or a finish, never work.

- [ ] **Step 4: Show it in the gallery**

In `DebugRender.swift`, `StatusMarkGallery`: add a tool to each entry and two entries.

```swift
    private static let states: [(String, AgentRowState, TimeInterval, AgentTool?)] = [
        ("working", .working, 0.2, nil),
        ("claude", .working, 0.2, .claudeCode),
        ("codex", .working, 0.5, .codex),
        ("compacting", .compacting, 0.3, nil),
        ("knock", .needsInput(prompt: nil), 0.15, nil),
        ("ripple", .needsInput(prompt: nil), 0.7, nil),
        ("finished", .finished, 0, nil),
        ("running", .running, 0, nil),
        ("idle", .idle, 0, nil),
    ]
```

```swift
                ForEach(Self.states, id: \.0) { name, state, time, tool in
                    VStack(spacing: 8) {
                        AgentStatusMark(state: state, size: 42, tool: tool, frozenAt: time)
                            .frame(width: 60, height: 60)
                        AgentStatusMark(state: state, tool: tool, frozenAt: time)
                        Text(name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                    }
                }
```

Widen the picture in `runIfRequested`: `StatusMarkGallery()` with `size: CGSize(width: 800, height: 150)`.

- [ ] **Step 5: Build, render, look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1
```

Expected: `** BUILD SUCCEEDED **`, tests pass. In `build/render/status-marks.png`: `working` is white as before; `claude` is an arc from amber to pink-red whose ends are round and not cut; `codex` is an arc from cyan to purple; the other marks are unchanged. In `build/render/working-aurora.png` and `collapsed-faces.png` the working marks are coloured. Report what you see.

- [ ] **Step 6: Commit**

```bash
git add Symbiodock
git commit -m "feat(island): turn the working arc in the tool's colours" -m "A white arc was the dullest thing on a working face. The colours stand still and the arc turns over them, so the arc changes colour as it goes."
git push origin main
```

---

### Task 7: The satellites

**Files:**
- Create: `Symbiodock/Island/Agents/MarkSatellites.swift`
- Modify: `Symbiodock/Island/Agents/AgentStatusMark.swift`
- Modify: `Symbiodock/Island/Agents/AgentFaces.swift` (three `AgentStatusMark(` calls)
- Modify: `Symbiodock/App/DebugRender.swift` (`StatusMarkGallery`, `WorkingAuroraGallery`)

**Interfaces:**
- Consumes: Task 3 `AgentSatellite`, `AgentSatellites.turn(of:at:)`, `AgentSatellites.stillTurn(index:count:)`, `AgentRow.orbiters`; Task 5 `AgentPalette.aurora(for:)`; `AgentPalette.mint`; `SharedClock.begin(in:)`.
- Produces: `struct MarkSatellites: View` with `init(orbiters: [AgentSatellite], tool: AgentTool, markSize: CGFloat = 14, frozenAt: TimeInterval? = nil)`; `AgentStatusMark.orbiters: [AgentSatellite]?` (nil by default: no satellites at all). `AgentStatusMark`'s memberwise order becomes `state, size, tool, orbiters, frozenAt`.

- [ ] **Step 1: The view**

Create `Symbiodock/Island/Agents/MarkSatellites.swift`:

```swift
import AppKit
import SwiftUI
import SymbiodockCore

/// The working sub-agents of a session, as small dots that circle its working mark, each at
/// its own pace (`AgentSatellites`). One that is new grows in; one that has finished stops,
/// turns mint, swells and goes. Live, each dot rides a layer that Core Animation turns
/// (`Orbits`); still (`frozenAt`, Reduce Motion) SwiftUI draws the dots where they stand.
struct MarkSatellites: View {
    let orbiters: [AgentSatellite]
    let tool: AgentTool
    /// The side of the mark they circle.
    var markSize: CGFloat = 14
    /// Draws the dots where they are this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let dot: CGFloat = 3
    /// Seconds a new dot takes to grow in.
    static let appear: TimeInterval = 0.4
    /// Seconds a finished dot takes to swell and go, and how large it swells.
    static let leave: TimeInterval = 0.9
    static let burst = 2.3

    /// From the mark's centre to a dot's centre: 11 pt for a mark of 14.
    static func radius(markSize: CGFloat) -> CGFloat { markSize * 11 / 14 }

    private var side: CGFloat { 2 * Self.radius(markSize: markSize) + Self.dot }

    var body: some View {
        Group {
            if frozenAt != nil || reduceMotion {
                still
            } else {
                Orbits(
                    orbiters: orbiters, colors: AgentPalette.aurora(for: tool).map { NSColor($0).cgColor },
                    dot: Self.dot)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var still: some View {
        let radius = Self.radius(markSize: markSize)
        let colors = AgentPalette.aurora(for: tool)
        return ZStack {
            ForEach(Array(orbiters.enumerated()), id: \.element.id) { index, satellite in
                let turn = frozenAt.map { AgentSatellites.turn(of: satellite, at: $0) }
                    ?? AgentSatellites.stillTurn(index: index, count: orbiters.count)
                Circle()
                    .fill(colors[satellite.tone % colors.count])
                    .frame(width: Self.dot, height: Self.dot)
                    .offset(x: radius * sin(2 * .pi * turn), y: -radius * cos(2 * .pi * turn))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: orbiters.map(\.id))
    }
}

/// The live dots. Each rides at the top of a layer as large as the view, and the layer
/// turns about its centre; the render server plays it.
private struct Orbits: NSViewRepresentable {
    let orbiters: [AgentSatellite]
    let colors: [CGColor]
    let dot: CGFloat

    func makeNSView(context: Context) -> OrbitView { OrbitView() }

    func updateNSView(_ view: OrbitView, context: Context) {
        view.configure(orbiters: orbiters, colors: colors, dot: dot)
    }

    static func dismantleNSView(_ view: OrbitView, coordinator: ()) {
        view.stop()
    }

    final class OrbitView: NSView {
        /// The turning layer of each satellite shown, by its id.
        private var carriers: [String: CALayer] = [:]
        private var orbiters: [AgentSatellite] = []
        private var colors: [CGColor] = []
        private var dot: CGFloat = 3

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(orbiters: [AgentSatellite], colors: [CGColor], dot: CGFloat) {
            self.colors = colors
            self.dot = dot
            self.orbiters = orbiters
            let wanted = Set(orbiters.map(\.id))
            // The mark is only there while its session works: a satellite that leaves while
            // the mark stays has finished.
            for id in carriers.keys where !wanted.contains(id) { finish(id) }
            for satellite in orbiters where carriers[satellite.id] == nil { add(satellite) }
        }

        /// Takes the motion down: no animation is left.
        func stop() {
            for carrier in carriers.values {
                carrier.removeAllAnimations()
                carrier.sublayers?.forEach { $0.removeAllAnimations() }
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for carrier in carriers.values { place(carrier) }
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stop()
            } else {
                for satellite in orbiters {
                    if let carrier = carriers[satellite.id] { turn(carrier, satellite) }
                }
            }
        }

        /// Sizes a carrier to the view and puts its dot at the top; the layer's y runs up.
        private func place(_ carrier: CALayer) {
            carrier.bounds = CGRect(origin: .zero, size: bounds.size)
            carrier.position = CGPoint(x: bounds.midX, y: bounds.midY)
            carrier.sublayers?.first?.position = CGPoint(x: bounds.width / 2, y: bounds.height - dot / 2)
        }

        private func add(_ satellite: AgentSatellite) {
            let carrier = CALayer()
            let point = CALayer()
            point.backgroundColor = colors.isEmpty ? NSColor.white.cgColor : colors[satellite.tone % colors.count]
            point.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
            point.cornerRadius = dot / 2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            carrier.addSublayer(point)
            place(carrier)
            layer?.addSublayer(carrier)
            CATransaction.commit()
            carriers[satellite.id] = carrier
            turn(carrier, satellite)
            guard window != nil else { return }
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0
            grow.toValue = 1
            grow.duration = MarkSatellites.appear
            grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            point.add(grow, forKey: "appear")
        }

        /// Starts a carrier turning, clockwise as seen: in a layer that is a fall in angle.
        private func turn(_ carrier: CALayer, _ satellite: AgentSatellite) {
            guard window != nil, carrier.animation(forKey: "orbit") == nil else { return }
            let start = -2 * Double.pi * satellite.phase
            let orbit = CABasicAnimation(keyPath: "transform.rotation.z")
            orbit.fromValue = start
            orbit.toValue = start - 2 * Double.pi
            orbit.duration = satellite.period
            orbit.repeatCount = .infinity
            orbit.timingFunction = CAMediaTimingFunction(name: .linear)
            orbit.beginTime = SharedClock.begin(in: carrier)
            orbit.isRemovedOnCompletion = false
            carrier.add(orbit, forKey: "orbit")
        }

        /// A satellite whose sub-agent has finished: it stops where it is, turns mint,
        /// swells and goes.
        private func finish(_ id: String) {
            guard let carrier = carriers.removeValue(forKey: id) else { return }
            guard window != nil, let point = carrier.sublayers?.first else {
                carrier.removeFromSuperlayer()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            carrier.transform = carrier.presentation()?.transform ?? carrier.transform
            carrier.removeAnimation(forKey: "orbit")
            point.backgroundColor = NSColor(AgentPalette.mint).cgColor
            point.opacity = 0
            CATransaction.commit()
            let swell = CAKeyframeAnimation(keyPath: "transform.scale")
            swell.values = [1, MarkSatellites.burst, 0]
            swell.keyTimes = [0, 0.3, 1]
            swell.duration = MarkSatellites.leave
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.3, 1]
            fade.duration = MarkSatellites.leave
            point.add(swell, forKey: "swell")
            point.add(fade, forKey: "fade")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(MarkSatellites.leave))
                carrier.removeFromSuperlayer()
            }
        }
    }
}
```

- [ ] **Step 2: The mark carries them**

In `AgentStatusMark.swift`, add a property after `tool`:

```swift
    /// The session's working sub-agents, which circle a working mark. Nil where the mark
    /// shows none at all (the list, whose rows name their sub-agents below).
    var orbiters: [AgentSatellite]?
```

In `body`, after `.frame(width: size, height: size)`:

```swift
            .overlay {
                // Kept while the session works, even with none: the last one still has to go.
                // The animation is on the container, which stays, so the satellites fade.
                ZStack {
                    if state == .working, let tool, let orbiters {
                        MarkSatellites(orbiters: orbiters, tool: tool, markSize: size, frozenAt: frozenAt)
                            .id(sessionID)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: state == .working)
            }
```

(An overlay takes no room: the mark's own frame stays `size`.)

`AgentStatusMark` also gets, after `orbiters`, `var sessionID: String?` ("The session the mark speaks for: its satellites belong to it, and a new session's are new."). Only the satellites carry it as their identity; the mark itself does not, or a new lead session would lose the finish ring and the spring between states.

- [ ] **Step 3: The collapsed faces pass them**

In `AgentFaces.swift`:

```swift
            AgentStatusMark(
                state: row.state, tool: row.session.tool, orbiters: row.orbiters, sessionID: row.id)
```

```swift
                AgentStatusMark(
                    state: row.isSettled ? .idle : row.state, tool: row.session.tool, orbiters: row.orbiters,
                    sessionID: row.id)
```

(the second form twice). `AgentsContent.swift` stays as Task 6 left it: no orbiters in the list.

- [ ] **Step 4: Show them in the galleries**

In `DebugRender.swift`, `StatusMarkGallery`: give the `claude` and `codex` entries satellites. Add a helper and use it:

```swift
    private static func orbiters(_ count: Int) -> [AgentSatellite] {
        let start = Date(timeIntervalSince1970: 0)
        return AgentSatellites.orbiters(
            for: (0..<count).map {
                AgentSubagent(id: "sub-\($0)", title: "", isFinished: false, since: start.addingTimeInterval(Double($0)))
            },
            state: .working)
    }
```

```swift
                        AgentStatusMark(
                            state: state, size: 42, tool: tool, orbiters: tool == nil ? nil : Self.orbiters(3),
                            frozenAt: time)
                            .frame(width: 80, height: 80)
                        AgentStatusMark(
                            state: state, tool: tool, orbiters: tool == nil ? nil : Self.orbiters(3), frozenAt: time)
                            .frame(width: 30, height: 30)
```

(the two frames grow from 60 and none, so that the dots are not cut off) and set the picture's size to `CGSize(width: 900, height: 180)`.

In `WorkingAuroraGallery.row(_:)`, give the session two working sub-agents so that every face in that picture shows satellites:

```swift
    private func row(_ tool: AgentTool) -> AgentRow {
        let now = Date()
        var session = AgentSession(
            id: "x", tool: tool, title: "fix-login-flow", projectPath: nil,
            activity: .working, since: now, pid: nil)
        session.subagents = [
            AgentSubagent(id: "one", title: "", isFinished: false, since: now.addingTimeInterval(-60)),
            AgentSubagent(id: "two", title: "", isFinished: false, since: now.addingTimeInterval(-20)),
        ]
        var board = AgentSessionBoard()
        board.update([session])
        return board.rows[0]
    }
```

- [ ] **Step 5: Build, render, look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1
```

Expected: `** BUILD SUCCEEDED **`, tests pass. Check:

1. `status-marks.png`: `claude` and `codex` have three dots on a circle round the arc, in three different colours, none cut off; the other marks have none.
2. `working-aurora.png`: every face has two dots round its working mark. At the notch they stay inside the wing; on the capsule they do not cover the title and stay inside the island; on the strip they stay inside the strip.
3. `expanded-agents.png`: no dots in the list.

If a dot is cut off by the island's edge on the capsule or the strip, widen that face's padding beside the mark in `AgentFaces.swift` (`.padding(.horizontal, ...)` of `AgentFloatingFace`, `.padding(.vertical, ...)` of `AgentSideFace`) by what is missing, render again, and say what you changed. Report what you see for each point.

- [ ] **Step 6: Run it live**

```bash
pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_AGENTS=working build/Build/Products/Debug/Symbiodock.app
sleep 4 && top -l 4 -stats pid,command,cpu -pid $(pgrep -x Symbiodock) | grep Symbiodock
pkill -x Symbiodock
```

(The `working` demo's lead is a Codex session with two working sub-agents.) Expected: no crash; the last three CPU samples about 0 (below 1.0). Report the numbers.

- [ ] **Step 7: Commit**

```bash
git add Symbiodock
git commit -m "feat(island): circle the working mark with its sub-agents" -m "The collapsed island said nothing about sub-agents. Each working one is now a dot that circles the mark at its own pace; one that finishes turns mint and goes."
git push origin main
```

---

### Task 8: Record it

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/plans/2026-11-20-working-aurora.md` (this file: tick the boxes, note anything that had to change)

**Interfaces:** none.

- [ ] **Step 1: The decision record**

In `CLAUDE.md`, in the table under `## Karar kaydı`, add these rows after the `Parça ışığı` row:

```markdown
| Çalışma ışığı | Agent çalışırken (kapalı ada, yüz agent, öndeki oturum `working`, dikkat yok) adanın serbest uzun kenarının hemen dışında aracın dört renginde akan bir ışık: 1 pt net çizgi ve 9 pt'ye kadar uzanan, nefes alan hale. Renkler 3,2 sn'de bir tur akar, hale 2,4 sn'de nefes alır. Adanın arkasında ayrı katman; soru, bitiş, compact ışığı varken ve agent baloncuktayken yanmaz. Reduce Motion'da sabit (2026-11-20) | Sahibi: "agent çalışırkenki animasyon çok sönük kaldı, basit yani"; dört tur canlı taslaktan "kuzey ışıkları güzel", sonra "Yedek 2 canlı. Bu olsun" dedi; kenar ve baloncuk kuralları öneriydi, "önerileri yap" (spec: `2026-11-20-working-aurora-design.md`) |
| Renkli yay ve uydular | Çalışan oturumun dönen yayı aracın ışık renklerinde (ilk renkten ikinciye; renk durur, yay döner). Kapalı adanın yüzlerinde çalışan her alt ajan yayın etrafında dönen 3 pt'lik nokta: en fazla 5, her biri kendi hızında (2,3-4,3 sn), biten nane yeşili parlayıp gider. Listede uydu yok. "Kapalı adada alt ajan göstergesi yok" kararı (2026-11-15) bununla değişti (2026-11-20) | Sahibi ilk turda "Fikir 3"ü (uydular) işaretledi; seçtiği kartta ikisi de vardı ve dahil edilmelerini onayladı |
| Canlı pet | Pet tonları parladı: gölgeler tam renge %38 yaklaştırıldı (`shadeLift` 0,62; en soluk ton %60), zemin çizgileri 0,12, dalgada bekleyen çizgi %92, çizgi payı 0,68; Claude Code, Codex, OpenCode ve Aider renkleri en parlak değerine çekildi (2026-11-20; önce en soluk ton %36, dalga %82) | Sahibi: "biraz daha canlı yapsana rengi çok soluk bu haliyle"; taslaktaki üç seviyeden `Canlı`yı seçti |
```

In the existing `Alt ajan dalları` row, change the sentence `Kapalı adada gösterge yok (2026-11-15)` to `Kapalı adada 2026-11-20'den beri uydular var (bkz. "Renkli yay ve uydular")`.

- [ ] **Step 2: The status**

In `CLAUDE.md`, under `## Durum`, add after the `Parça ışığı` entry. Fill in the test count from `swift test` and the CPU numbers and render findings from Tasks 5-7; do not write a number you did not measure:

```markdown
- **Çalışma ışığı, renkli yay, uydular, canlı pet (2026-11-20, <N> çekirdek testi): kod `main`'de.** Ekran dışı görüntülerde doğrulandı (`working-aurora.png`: çentikte iki araç, nefesin iki ucu, alt kenarda kapsül, sağ kenarda şerit, canlı katmanların duruşu; `status-marks.png`; `pets.png`). Demo ile canlıda çökmeden çalıştı; CPU: <ölçülen>. Canlı görünüm görülemedi (ekran görüntüsü pencereleri göstermiyor): akışın hızı, halenin gücü, uyduların okunurluğu ve pet'in yeni parlaklığı sahibinin elle kontrolüne kaldı. Deneme: `SYMBIODOCK_DEMO_AGENTS=working` (Codex, iki çalışan alt ajan). Liste: `docs/superpowers/plans/2026-11-20-working-aurora.md` sonunda.
```

- [ ] **Step 3: Verify everything once more**

```bash
swift test --package-path Packages/SymbiodockCore 2>&1 | tail -1
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
git status --short
```

Expected: all tests pass, `** BUILD SUCCEEDED **`, only `CLAUDE.md` and this plan modified.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/superpowers/plans/2026-11-20-working-aurora.md
git commit -m "docs: record the light of a working agent" -m "The decision table and the status say what was chosen, what was verified offscreen and what is left for the owner to look at."
git push origin main
```

---

## Elle kontrol listesi

Uygulama: `open --env SYMBIODOCK_DEMO_AGENTS=working build/Build/Products/Debug/Symbiodock.app` (Codex, iki çalışan alt ajan). Gerçek oturumla da denenebilir: Claude Code'da uzun bir iş başlat.

1. Agent çalışırken çentiğin altında renkli bir ışık var; ince çizgi adanın hemen altında, hale aşağı doğru sönüyor.
2. Renkler soldan sağa akıyor; hale nefes alıyor. Hız ve güç gözü yormuyor.
3. Işık adanın siyahının üstüne taşmıyor ve altındaki menüye ya da pencereye tıklamayı engellemiyor.
4. Fareyle adanın üstüne gelince ada açılıyor, ışık yerinde sönüyor; ayrılınca ışık doğrudan adanın kenarında beliriyor (aşağıdan ya da yandan kayarak gelmiyor).
5. Claude Code'da ışık turuncu-pembe, Codex'te mavi-mor.
6. Agent soru sorunca ışık gidiyor, amber ışık geliyor; cevaplayınca geri dönüyor.
7. Agent bitince ışık gidiyor, Face ID bitiş efekti oynuyor.
8. `/compact` sırasında ışık yok, mor kesikli çizgi var.
9. Müzik de çalıyorsa ve agent sol baloncuktaysa ışık yok.
10. Adayı alt kenara sürükle: ışık kapsülün üst kenarında. Sağ ya da sol kenara sürükle: ışık şeridin içeri bakan kenarında, renkler yukarıdan aşağı akıyor.
11. Sağdaki dönen yay beyaz değil, aracın renklerinde; dönerken rengi değişiyor.
12. Çalışan her alt ajan için yayın etrafında bir nokta dönüyor; noktalar farklı hızda.
13. Yeni bir alt ajan başlayınca nokta büyüyerek beliriyor; biri bitince noktası yeşile dönüp kayboluyor.
14. Açık adadaki listede nokta yok, yay orada da renkli.
15. Pet'ler eskisinden canlı; yine de kabartma hissi (ışık alan ve gölgede kalan taraf) duruyor.
16. Çalışan pet'in soldan sağa dalgası hâlâ seçiliyor (bekleyen çizgiler artık %92'de duruyor, fark küçüldü).
17. Sistem Ayarları'nda Hareketi Azalt açıkken ışık sabit duruyor, noktalar dönmüyor.
18. Agent çalışırken Etkinlik Monitörü'nde Symbiodock'un CPU'su %0-1 civarında.
