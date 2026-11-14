# Milestone 3, part 1: Drag and Snap Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Follow TDD in every task: write the listed tests first, watch them fail, implement, watch them pass.

**Goal:** Everything milestone 3 needs that can be proven without looking at the screen: anchors, snapping, floating layout, the drag state machine and a testable hover debounce — all in `SymbiodockCore`, all unit-tested.

**Scope decision (owner, 2026-11-14):** the window and gesture side of milestone 3 (`DragController`, moving the island, persisting through `UserDefaults`, "Return to notch" in the menu) is NOT in this plan. It gets its own plan after the owner has seen milestone 2 on screen. This plan must leave the app's behaviour unchanged.

**Architecture:** New pure types next to the existing ones in `Packages/SymbiodockCore/Sources/SymbiodockCore/`. Existing public API keeps working (the app still calls `IslandLayout.frame(phase:notch:screenSize:hasTrack:)` and `IslandState.setHovering`). New API is added beside it; the app migrates in part 2.

**Spec:** `docs/superpowers/specs/2026-11-14-symbiodock-v1-design.md`, sections 5.2–5.5 and 7.

## Global Constraints

- `SymbiodockCore` must not import AppKit or SwiftUI. Swift 6, macOS 14.
- All geometry handed to the new functions is in panel-local coordinates: origin at the top-left of the display, y grows downward, points. `ScreenMetrics.frame` and `ScreenMetrics.visibleFrame` are the only values in AppKit global coordinates (origin bottom-left, y up).
- Numbers (spec): notch capture radius 120 pt from the notch center; corner capture radius 80 pt from a corner of the visible frame; tear distance 120 pt; floating island sits 8 pt inside the visible frame; expanded island 360 × 150 pt.
- Number (this plan; not in the spec): the floating island's collapsed size is 200 × 36 pt.
- Hover timing stays 80 ms in / 250 ms out (`HoverTiming`).
- All code, identifiers and comments in English. Tests use Swift Testing. Every public symbol gets a one-line doc comment that says what it is for.
- Test command: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`. Build command (the app must still build, with no warnings from our code): `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | grep -E "warning:|error:|BUILD" | sort -u`.
- Commits: Conventional Commits, title ≤ 72 characters, imperative; one commit per task; push to `main` after each. Never commit `Symbiodock.xcodeproj` or `build/`.

## File Structure

```
Packages/SymbiodockCore/Sources/SymbiodockCore/
  IslandAnchor.swift        ScreenEdge, ScreenCorner, IslandAnchor, AnchorCodec
  ScreenMetrics.swift       (modify) visibleFrame, localRect(fromGlobal:), localVisibleFrame
  SnapResolver.swift        release point → anchor
  IslandLayout.swift        (modify) frames for floating anchors
  IslandState.swift         (modify) anchor, drag phases and transitions
  HoverDebounce.swift       hover delay logic with an injected clock
Packages/SymbiodockCore/Tests/SymbiodockCoreTests/
  IslandAnchorTests.swift, SnapResolverTests.swift, HoverDebounceTests.swift (new)
  ScreenMetricsTests.swift, IslandLayoutTests.swift, IslandStateTests.swift (modify)
Symbiodock/Window/NSScreen+Metrics.swift   (modify) pass visibleFrame
Symbiodock/Island/IslandView.swift         (modify) only to keep its switch exhaustive
```

---

### Task 1: Anchors, their codec, and the visible frame

**Interfaces produced:**

```swift
public enum ScreenEdge: String, Codable, Sendable, CaseIterable { case top, bottom, left, right }
public enum ScreenCorner: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}
public enum IslandAnchor: Equatable, Codable, Sendable {
    case notch
    case edge(ScreenEdge, fraction: Double)   // 0...1 along the edge, from left or from top
    case corner(ScreenCorner)
}
public enum AnchorCodec {
    public static func encode(_ anchor: IslandAnchor) -> Data
    /// Anything that cannot be decoded is `.notch`; an edge fraction is clamped to 0...1.
    public static func decode(_ data: Data?) -> IslandAnchor
}
```

`ScreenMetrics` gains a stored `public var visibleFrame: CGRect` (AppKit global coordinates), a new initializer parameter `visibleFrame:` placed right after `frame:`, and:

```swift
public func localRect(fromGlobal rect: CGRect) -> CGRect   // flips y, removes the screen origin
public var localVisibleFrame: CGRect { localRect(fromGlobal: visibleFrame) }
```

Update every existing `ScreenMetrics(...)` call (tests and `Symbiodock/Window/NSScreen+Metrics.swift`, which passes `screen.visibleFrame`).

**Tests:**

| Test | Given | Expect |
|---|---|---|
| anchorsSurviveARoundTrip | each of `.notch`, `.edge(.left, fraction: 0.25)`, `.corner(.bottomRight)` | `decode(encode(a)) == a` |
| undecodableDataFallsBackToTheNotch | `nil`, empty `Data`, `Data("junk".utf8)` | `.notch` |
| edgeFractionIsClampedWhenDecoding | encoded `.edge(.top, fraction: 1.7)` and `.edge(.top, fraction: -3)` | `.edge(.top, fraction: 1)` and `.edge(.top, fraction: 0)` |
| localRectFlipsYAndRemovesTheOrigin | frame `(0, 982, 1920, 1080)`, global rect `(100, 1000, 300, 50)` | `(100, 1012, 300, 50)` |
| localVisibleFrameExcludesMenuBarAndDock | frame `(0, 0, 1512, 982)`, visibleFrame `(0, 70, 1512, 880)` | `(0, 32, 1512, 880)` |

Commit: `feat(core): add island anchors, their codec and the visible frame`

---

### Task 2: SnapResolver

**Interface produced:**

```swift
public enum SnapResolver {
    public static let notchCaptureRadius: CGFloat = 120
    public static let cornerCaptureRadius: CGFloat = 80
    /// Where the island settles when it is released at `point` (panel-local coordinates).
    public static func anchor(forRelease point: CGPoint, notch: CGRect, visibleFrame: CGRect) -> IslandAnchor
}
```

Rules, in order:

1. Distance from `point` to the notch's center ≤ 120 → `.notch`.
2. Distance from `point` to a corner of `visibleFrame` ≤ 80 → that `.corner` (the nearest one if more than one qualifies).
3. Otherwise the nearest edge of `visibleFrame`, measured as the distance to the edge's line (`|x − minX|`, `|x − maxX|`, `|y − minY|`, `|y − maxY|`); ties go to the first of top, bottom, left, right. `fraction` is the position along that edge, clamped to 0...1: `(x − minX) / width` for top and bottom, `(y − minY) / height` for left and right.

**Tests** — use `notch = (662, 0, 188, 32)` (center `(756, 16)`) and `visibleFrame = (0, 32, 1512, 880)` (corners `(0, 32)`, `(1512, 32)`, `(0, 912)`, `(1512, 912)`):

| Test | Point | Expect |
|---|---|---|
| releaseNearTheNotchReturnsToIt | `(756, 100)` | `.notch` |
| notchCaptureBoundaryIsInclusive | `(756, 136)` → `.notch`; `(756, 137)` → not `.notch` | as stated |
| eachCornerCaptures | `(30, 60)`, `(1490, 60)`, `(30, 890)`, `(1490, 890)` | `.topLeft`, `.topRight`, `.bottomLeft`, `.bottomRight` |
| cornerCaptureBoundaryIsInclusive | `(80, 32)` → `.corner(.topLeft)`; `(81, 32)` → `.edge(.top, …)` | as stated |
| nearestEdgeWins | `(400, 300)` → `.edge(.top, fraction: 400/1512)`; `(400, 800)` → `.edge(.bottom, fraction: 400/1512)`; `(100, 500)` → `.edge(.left, fraction: 468/880)`; `(1400, 500)` → `.edge(.right, fraction: 468/880)` | compare fractions with a tolerance of 1e-9 |
| pointOutsideTheVisibleFrameIsClamped | `(-50, 500)` → `.edge(.left, fraction: 468/880)`; `(700, 1000)` → `.edge(.bottom, fraction: 700/1512)` | fraction stays within 0...1 |

Commit: `feat(core): resolve a release point to an anchor`

---

### Task 3: Layout for floating anchors

**Interface produced** (the existing `frame(phase:notch:screenSize:hasTrack:)` and `hitRect(phase:notch:screenSize:hasTrack:)` stay public and unchanged):

```swift
extension IslandLayout {
    public static let floatingCollapsedSize = CGSize(width: 200, height: 36)
    public static let floatingInset: CGFloat = 8

    public static func frame(
        anchor: IslandAnchor, phase: IslandPhase, notch: CGRect,
        visibleFrame: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect

    public static func hitRect(
        anchor: IslandAnchor, phase: IslandPhase, notch: CGRect,
        visibleFrame: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect    // the frame grown by hitPadding
}
```

Rules:

- `.notch` → exactly what the existing notch function returns for `.collapsed` and `.expanded`.
- For this function every phase other than `.expanded` is laid out as collapsed (the drag phases arrive in Task 4; write the `switch` so that adding them does not change results).
- Floating size: `floatingCollapsedSize` when collapsed (always, with or without a track: a floating island must stay visible and draggable), `expandedSize` when expanded.
- Let `usable = visibleFrame.insetBy(dx: 8, dy: 8)`, `w`/`h` the size.
  - `.edge(.top, f)`: `x = usable.minX + f · (usable.width − w)`, `y = usable.minY`
  - `.edge(.bottom, f)`: same `x`, `y = usable.maxY − h`
  - `.edge(.left, f)`: `x = usable.minX`, `y = usable.minY + f · (usable.height − h)`
  - `.edge(.right, f)`: `x = usable.maxX − w`, same `y`
  - `.corner(c)`: `x` and `y` pinned to that corner of `usable`
  - `f` is clamped to 0...1. Because the pinned side does not move, expanding grows toward the inside of the screen.

**Tests** — `notch = (662, 0, 188, 32)`, `visibleFrame = (0, 32, 1512, 880)` (so `usable = (8, 40, 1496, 864)`), `screenSize = (1512, 982)`:

| Test | Input | Expect |
|---|---|---|
| notchAnchorMatchesTheNotchLayout | `.notch`, collapsed and expanded, `hasTrack` false and true | equal to the existing function's results |
| floatingCollapsedIslandIsACapsuleInsideTheVisibleFrame | `.corner(.topLeft)` → `(8, 40, 200, 36)`; `.corner(.bottomRight)` → `(1304, 868, 200, 36)` | as stated |
| floatingIslandIgnoresWhetherThereIsATrack | `.corner(.topLeft)`, collapsed, `hasTrack` false vs true | equal |
| edgeFractionSlidesAlongTheEdge | `.edge(.top, 0)` → `(8, 40, 200, 36)`; `.edge(.top, 1)` → `(1304, 40, 200, 36)`; `.edge(.top, 0.5)` → `(656, 40, 200, 36)`; `.edge(.left, 0.5)` → `(8, 454, 200, 36)`; `.edge(.right, 1)` → `(1304, 868, 200, 36)`; `.edge(.bottom, 0)` → `(8, 868, 200, 36)` | as stated |
| expandingGrowsTowardTheInside | `.corner(.bottomRight)` expanded → `(1144, 754, 360, 150)`; `.edge(.bottom, 0.5)` expanded → `(576, 754, 360, 150)`; `.edge(.right, 0)` expanded → `(1144, 40, 360, 150)` | as stated |
| floatingHitRectIsTheFrameGrownByFourPoints | `.corner(.topLeft)` collapsed | `(4, 36, 208, 44)` |

Commit: `feat(core): lay out the island at edges and corners`

---

### Task 4: Drag phases and transitions in IslandState

**Interface produced:**

```swift
public enum IslandPhase: Equatable, Sendable {
    case collapsed, expanded
    case stretching   // being dragged, still attached to its anchor
    case detached     // being dragged, torn off
    case settling     // released, animating to the target anchor
}

extension IslandState {
    public static let tearDistance: CGFloat   // 120
    public private(set) var anchor: IslandAnchor          // starts as .notch
    public private(set) var dragLocation: CGPoint?        // non-nil only while stretching or detached
    public private(set) var dragOrigin: CGPoint?          // where the island was attached when the drag began

    public var isDragging: Bool                           // stretching or detached

    public func restoreAnchor(_ anchor: IslandAnchor)     // at launch; only while collapsed or expanded
    public func beginDrag(at point: CGPoint, from origin: CGPoint)
    /// Returns true exactly once per drag: on the update that tears the island off.
    @discardableResult public func drag(to point: CGPoint) -> Bool
    public func endDrag(resolvedAnchor: IslandAnchor)
    public func finishSettling()
}
```

(`anchor`, `dragLocation`, `dragOrigin` are stored properties of the class, not of an extension; the extension notation above only groups the new API.)

Transitions (spec 5.3):

| From | Event | To |
|---|---|---|
| collapsed / expanded | `beginDrag` | stretching; `dragOrigin` and `dragLocation` set |
| stretching | `drag(to:)` with distance from `dragOrigin` > 120 | detached; returns true |
| stretching | `drag(to:)` otherwise | stretching; returns false |
| detached | `drag(to:)` | detached (it never re-attaches during the same drag); returns false |
| stretching | `endDrag` | settling; anchor unchanged, whatever `resolvedAnchor` says |
| detached | `endDrag` | settling; anchor = `resolvedAnchor` |
| settling | `finishSettling` | collapsed |

Everything else is ignored without changing state: `beginDrag` while dragging or settling, `drag`/`endDrag` when not dragging, `finishSettling` when not settling, `restoreAnchor` while dragging or settling. `endDrag` clears `dragLocation` and `dragOrigin`. **`setHovering` is ignored unless the phase is collapsed or expanded** — a late hover timer must not cancel a drag. The island is always collapsed after a drag.

Keep `Symbiodock/Island/IslandView.swift` compiling without changing what it shows: its `switch state.phase` treats the three new phases like `.collapsed`, and its corner radius stays "24 when expanded, otherwise 10". Do not touch anything else in the app.

**Tests** (add to `IslandStateTests.swift`; `origin = (756, 16)`):

| Test | Steps | Expect |
|---|---|---|
| startsAtTheNotchAndNotDragging | new state | `anchor == .notch`, `!isDragging`, `dragLocation == nil` |
| dragBeginsFromCollapsedAndFromExpanded | `beginDrag` from collapsed; from expanded | phase `.stretching`, `dragLocation` set, both times |
| pullingPastTheTearDistanceDetachesOnce | `drag(to: (756, 136))` → false, stretching; `drag(to: (756, 137))` → true, detached; `drag(to: (756, 300))` → false, detached | as stated |
| detachedIslandDoesNotReattachDuringTheDrag | after tearing, `drag(to: origin)` | still `.detached` |
| releasingWhileAttachedSnapsBackToTheSameAnchor | stretching, `endDrag(resolvedAnchor: .corner(.topLeft))` | phase `.settling`, `anchor == .notch`, `dragLocation == nil` |
| releasingWhileDetachedMovesToTheResolvedAnchor | detached, `endDrag(resolvedAnchor: .corner(.topLeft))`, `finishSettling()` | `.settling` then `.collapsed`, `anchor == .corner(.topLeft)` |
| hoverIsIgnoredWhileDraggingAndSettling | `setHovering(true)` while stretching, detached, settling | phase unchanged each time |
| eventsOutOfOrderAreIgnored | `drag`, `endDrag`, `finishSettling` on a fresh state; `beginDrag` twice | no state change; second `beginDrag` keeps the first origin |
| restoreAnchorAppliesOnlyWhenIdle | `restoreAnchor(.edge(.left, fraction: 0.5))` when collapsed → applied; while stretching → ignored | as stated |

Commit: `feat(core): add drag phases and transitions to the island state`

---

### Task 5: HoverDebounce

The hover delay currently lives untested inside `OverlayController`. This task adds the pure replacement; the app adopts it in part 2.

**Interface produced:**

```swift
/// Turns raw "pointer is inside / outside" samples into delayed hover changes.
public struct HoverDebounce<Instant: InstantProtocol> where Instant.Duration == Duration {
    public private(set) var isHovering: Bool        // the debounced value; starts false
    public init()
    /// Feed a sample. Returns the instant at which `fire(now:)` should be called, or nil
    /// if nothing is pending (the sample matches the current value, or cancels a pending change).
    public mutating func pointer(inside: Bool, now: Instant) -> Instant?
    /// Applies the pending change if its deadline has passed. Returns the new value when it changed.
    public mutating func fire(now: Instant) -> Bool?
    /// Drops any pending change and sets the value (used when the panel is rebuilt).
    public mutating func reset(to hovering: Bool)
}
```

Rules: a sample that differs from `isHovering` schedules a change at `now + HoverTiming.enterDelay` (to true) or `now + HoverTiming.exitDelay` (to false), unless the same change is already pending (then the original deadline is returned unchanged). A sample equal to `isHovering` cancels any pending change. `fire` before the deadline does nothing and returns nil.

**Tests** (use `ContinuousClock.Instant`; `t0 = ContinuousClock.now`, later instants via `t0.advanced(by:)`):

| Test | Steps | Expect |
|---|---|---|
| enteringTakesEightyMilliseconds | `pointer(inside: true, now: t0)` → `t0 + 80 ms`; `fire(now: t0 + 79 ms)` → nil; `fire(now: t0 + 80 ms)` → true | `isHovering` true at the end |
| leavingTakesAQuarterSecond | after hovering, `pointer(inside: false, now: t1)` → `t1 + 250 ms`; `fire(now: t1 + 250 ms)` → false | `isHovering` false |
| aQuickSweepNeverOpens | `pointer(true, t0)`, `pointer(false, t0 + 40 ms)` → nil, `fire(now: t0 + 200 ms)` → nil | `isHovering` false |
| comingBackBeforeTheExitDelayKeepsItOpen | hovering; `pointer(false, t1)`, `pointer(true, t1 + 100 ms)` → nil, `fire(now: t1 + 300 ms)` → nil | `isHovering` true |
| repeatedSamplesKeepTheOriginalDeadline | `pointer(true, t0)`, `pointer(true, t0 + 50 ms)` → `t0 + 80 ms` | as stated |
| resetDropsThePendingChange | `pointer(true, t0)`, `reset(to: false)`, `fire(now: t0 + 1 s)` → nil | `isHovering` false |

Commit: `feat(core): add a testable hover debounce`

---

## After Task 5

Run the test command (expect every test to pass, three times) and the build command (expect `** BUILD SUCCEEDED **`, no warnings from our code). Relaunch the app (`pkill -x Symbiodock; sleep 2; open build/Build/Products/Debug/Symbiodock.app`, retry `open` once on error -600) and leave it running. The app's behaviour must be unchanged.

## Not in this plan (part 2, after the owner has seen milestone 2)

`DragController` and the drag gesture on the island; moving the island with the pointer; saving and restoring the anchor through `UserDefaults`; "Return to notch" in the island menu; haptics; adopting `HoverDebounce` and the anchor-aware layout in `OverlayController` and `IslandView`; the floating capsule's look.
