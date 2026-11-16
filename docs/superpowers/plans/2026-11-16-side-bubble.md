# Side Bubble Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While both tabs have a collapsed face at the notch, the second tab's face moves out to a round bubble left of the island; hovering the bubble opens the island on that tab.

**Architecture:** The decision (which tab is in the bubble), its frame and its hit rect are pure functions in `SymbiodockCore`, tested with `swift test`. The app draws the bubble in the existing full-screen panel, below the island, and the overlay controller adds the bubble's hit rect to the hover test.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing.

Spec: `docs/superpowers/specs/2026-11-16-side-bubble-design.md`.

## Global Constraints

- Minimum macOS 14.0. No new dependencies.
- Interface text in English only.
- Only at the notch, only while collapsed. Docked islands are unchanged.
- The island's right wing, `RimLight` and `CompactingRim` are not touched.
- Nothing redraws per frame at rest.
- Bubble: diameter 28 pt (notch height − 4 if the notch is shorter than 32 pt), 6 pt left of the island with wings, centred in the notch band. Second source: 84 % size, 70 % artwork opacity, peeking 36 % of the diameter to the left.

---

### Task 1: Core — which tab is in the bubble, where it is

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandTab.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandLayout.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandTabTests.swift`, `IslandStateTests.swift`, `IslandLayoutTests.swift`

**Interfaces — produces:**
- `TabSelection.bubble(order: [IslandTab], mediaHasFace: Bool, agentsHasFace: Bool) -> IslandTab?`
- `IslandState.bubbleTab: IslandTab?`
- `IslandState.setHovering(_ hovering: Bool, opening tab: IslandTab? = nil)`
- `IslandLayout.bubbleGap`, `bubbleBehindScale`, `bubbleDiameter(notch:)`, `bubblePeek(diameter:)`, `bubbleFrame(notch:screenSize:)`, `bubbleHitRect(notch:screenSize:hasBehind:)`

- [ ] **Step 1: Write the failing tests**

`IslandTabTests.swift`:

```swift
    @Test func theBubbleTakesTheSecondTabWhenBothHaveAFace() {
        let agentsFirst: [IslandTab] = [.agents, .media]
        let mediaFirst: [IslandTab] = [.media, .agents]
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: true, agentsHasFace: true) == .media)
        #expect(TabSelection.bubble(order: mediaFirst, mediaHasFace: true, agentsHasFace: true) == .agents)
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: true, agentsHasFace: false) == nil)
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: false, agentsHasFace: true) == nil)
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: false, agentsHasFace: false) == nil)
    }
```

`IslandStateTests.swift` (uses the file's `track(playing:)` and `agent(_:_:)` helpers):

```swift
    @Test func theBubbleHoldsTheSecondFaceAtTheCollapsedNotch() {
        let state = IslandState()
        #expect(state.bubbleTab == nil)
        state.setNowPlaying(track(playing: true))
        #expect(state.bubbleTab == nil)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.face == .agents)
        #expect(state.bubbleTab == .media)
        state.setTabOrder([.media, .agents])
        #expect(state.face == .media)
        #expect(state.bubbleTab == .agents)
    }

    @Test func theBubbleGoesWhileTheIslandIsOpenOrAwayFromTheNotch() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        state.setHovering(true)
        #expect(state.bubbleTab == nil)
        state.setHovering(false)
        #expect(state.bubbleTab == .media)
        state.restoreAnchor(.edge(.bottom, fraction: 0.5))
        #expect(state.bubbleTab == nil)
    }

    @Test func hoveringTheBubbleOpensItsTabEvenOverAttention() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        state.setHovering(true, opening: .media)
        #expect(state.phase == .expanded)
        #expect(state.selectedTab == .media)
    }
```

`IslandLayoutTests.swift`:

```swift
    @Test func theBubbleSitsLeftOfTheWingsCentredInTheNotchBand() {
        // The island with wings starts at 662 − 36 = 626.
        #expect(IslandLayout.bubbleFrame(notch: notch, screenSize: screen)
            == CGRect(x: 592, y: 2, width: 28, height: 28))
    }

    @Test func theBubbleShrinksWithAShortNotch() {
        let short = CGRect(x: 662, y: 0, width: 188, height: 24)
        #expect(IslandLayout.bubbleDiameter(notch: short) == 20)
        #expect(IslandLayout.bubbleFrame(notch: short, screenSize: screen)
            == CGRect(x: 600, y: 2, width: 20, height: 20))
    }

    @Test func theBubbleHitRectCoversTheSourceBehind() {
        #expect(IslandLayout.bubbleHitRect(notch: notch, screenSize: screen, hasBehind: false)
            == CGRect(x: 588, y: -2, width: 36, height: 36))
        // The source behind shows round(28 × 0.36) = 10 pt further left.
        #expect(IslandLayout.bubbleHitRect(notch: notch, screenSize: screen, hasBehind: true)
            == CGRect(x: 578, y: -2, width: 46, height: 36))
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: compile errors (`bubble`, `bubbleTab`, `bubbleFrame` not found).

- [ ] **Step 3: Implement**

`IslandTab.swift`, inside `TabSelection`:

```swift
    /// The tab whose face moves out to the bubble beside the island: the second in order,
    /// while both have a face. Nil while at most one has.
    public static func bubble(
        order: [IslandTab], mediaHasFace: Bool, agentsHasFace: Bool
    ) -> IslandTab? {
        guard mediaHasFace, agentsHasFace else { return nil }
        switch face(order: order, mediaHasFace: true, agentsHasFace: true) {
        case .agents: return .media
        case .media: return .agents
        case .none: return nil
        }
    }
```

`IslandState.swift`, after `face`:

```swift
    /// The tab shown in the round bubble beside the island: the one that has a face but
    /// is not the island's. Only at the notch and only while collapsed.
    public var bubbleTab: IslandTab? {
        guard anchor == .notch, phase == .collapsed else { return nil }
        return TabSelection.bubble(
            order: tabOrder, mediaHasFace: mediaWings, agentsHasFace: board.hasFace)
    }
```

and `setHovering` becomes:

```swift
    /// Called after the hover delay has elapsed, not on every pointer move.
    /// Ignored unless the island is collapsed or expanded, so a late timer cannot cancel a drag.
    /// `tab` is the tab to open on when the pointer rests on the bubble; nil lets the usual
    /// rule choose.
    public func setHovering(_ hovering: Bool, opening tab: IslandTab? = nil) {
        guard phase == .collapsed || phase == .expanded else { return }
        if hovering, phase == .collapsed {
            selectedTab = tab ?? TabSelection.tabToOpen(
                order: tabOrder, attention: board.attention,
                mediaHasContent: nowPlaying != nil, agentsHasContent: !board.rows.isEmpty)
        }
        if !hovering, phase == .expanded { leaveSelectedTab() }
        phase = hovering ? .expanded : .collapsed
    }
```

`IslandLayout.swift`, new extension at the end of the first extension's file:

```swift
extension IslandLayout {
    /// Gap (pt) between the island and the bubble beside it.
    public static let bubbleGap: CGFloat = 6
    /// The bubble's diameter where the notch is tall enough for it.
    public static let bubbleMaxDiameter: CGFloat = 28
    /// Size of the second source's disc behind the bubble, relative to the bubble.
    public static let bubbleBehindScale: CGFloat = 0.84

    /// The bubble never reaches the edges of the notch band.
    public static func bubbleDiameter(notch: CGRect) -> CGFloat {
        min(bubbleMaxDiameter, max(notch.height - 4, 0))
    }

    /// How far the second source's disc shows past the bubble on the left.
    public static func bubblePeek(diameter: CGFloat) -> CGFloat {
        (diameter * 0.36).rounded()
    }

    /// The bubble: left of the island with its wings, centred in the notch band.
    public static func bubbleFrame(notch: CGRect, screenSize: CGSize) -> CGRect {
        let island = frame(phase: .collapsed, notch: notch, screenSize: screenSize, showsWings: true)
        let diameter = bubbleDiameter(notch: notch)
        return CGRect(
            x: island.minX - bubbleGap - diameter, y: notch.minY + (notch.height - diameter) / 2,
            width: diameter, height: diameter)
    }

    /// The area in which the pointer counts as hovering the bubble, with the disc behind it.
    public static func bubbleHitRect(notch: CGRect, screenSize: CGSize, hasBehind: Bool) -> CGRect {
        var rect = bubbleFrame(notch: notch, screenSize: screenSize)
        if hasBehind {
            let peek = bubblePeek(diameter: rect.width)
            rect.origin.x -= peek
            rect.size.width += peek
        }
        return rect.insetBy(dx: -hitPadding, dy: -hitPadding)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: all pass (408 + 7).

- [ ] **Step 5: Commit and push**

```bash
git add Packages docs/superpowers
git commit -m "feat(core): decide and place the bubble beside the island"
git push origin main
```

---

### Task 2: App — draw the bubble and hover it

**Files:**
- Create: `Symbiodock/Island/SideBubble.swift`
- Modify: `Symbiodock/Island/ArtworkView.swift` (round option)
- Modify: `Symbiodock/Island/Agents/AgentFaces.swift` (`AgentFacePet`, `AgentFaceLabel` shared; pet takes a size)
- Modify: `Symbiodock/Island/IslandView.swift`
- Modify: `Symbiodock/Window/OverlayController.swift`
- Modify: `Symbiodock/App/DebugRender.swift`

**Interfaces — consumes:** everything Task 1 produces.

- [ ] **Step 1: Round artwork**

In `ArtworkView` add `var isRound = false` after `size`, and replace the clip and hairline:

```swift
        .frame(width: size, height: size)
        .clipShape(outline)
        // A hairline keeps dark artwork from melting into the black island.
        .overlay {
            if isRound {
                Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    private var outline: AnyShape {
        isRound
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
```

- [ ] **Step 2: Share the face pet**

In `AgentFaces.swift`: drop `private` from `AgentFaceLabel` and `AgentFacePet`; give the pet a size:

```swift
struct AgentFacePet: View {
    let row: AgentRow
    var size: CGFloat = 24

    var body: some View {
        if row.state == .finished, !row.isSettled {
            FinishSeal(tool: row.session.tool, size: size)
                .id(row.id)
        } else {
            // A settled finish has ended its mark: the plain pet, quiet.
            AgentPet(tool: row.session.tool, state: row.isSettled ? .idle : row.state, size: size)
        }
    }
}
```

- [ ] **Step 3: `SideBubble.swift`**

```swift
import SwiftUI
import SymbiodockCore

/// The round bubble beside the collapsed island: the face of the tab the island itself is
/// not showing. Music is its artwork as a disc, with a second source as a smaller disc
/// showing behind it on the left; an agent is its pet.
struct SideBubble: View {
    enum Content {
        case media(front: NowPlayingInfo, behind: NowPlayingInfo?)
        case agent(AgentRow)
    }

    let content: Content
    let diameter: CGFloat

    /// Black kept around the artwork, so that it reads as a bubble and not as a cut-out.
    private static let rim: CGFloat = 3

    var body: some View {
        let small = diameter * IslandLayout.bubbleBehindScale
        let peek = IslandLayout.bubblePeek(diameter: diameter)

        ZStack(alignment: .trailing) {
            if case .media(_, let behind?) = content {
                disc(small) {
                    ArtworkView(
                        data: behind.artworkData,
                        size: small - 2 * Self.rim * IslandLayout.bubbleBehindScale, isRound: true)
                        .opacity(0.7)
                }
                .padding(.trailing, diameter - small + peek)
                .transition(.opacity.combined(with: .offset(x: peek)))
            }
            disc(diameter) {
                switch content {
                case .media(let front, _):
                    ArtworkView(data: front.artworkData, size: diameter - 2 * Self.rim, isRound: true)
                case .agent(let row):
                    AgentFacePet(row: row, size: (diameter * 0.64).rounded())
                }
            }
        }
        // The disc behind hangs out on the left; the bubble's own frame is the front disc.
        .frame(width: diameter, height: diameter, alignment: .trailing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasBehind)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var hasBehind: Bool {
        if case .media(_, _?) = content { true } else { false }
    }

    private var label: String {
        switch content {
        case .media(let front, _): "Now playing, \(front.title)"
        case .agent(let row): AgentFaceLabel.text(for: row)
        }
    }

    private func disc(_ size: CGFloat, @ViewBuilder _ inside: () -> some View) -> some View {
        inside()
            .frame(width: size, height: size)
            .background(.black, in: Circle())
            .clipShape(Circle())
    }
}
```

- [ ] **Step 4: Draw it in `IslandView`**

`body`'s `GeometryReader` content becomes a `ZStack(alignment: .topLeading)` with `bubble` first (so the island covers it) and the existing `switch` second. Add:

```swift
    /// The second face, in a bubble left of the island. It comes out from behind the
    /// island's left edge and goes back the same way.
    private var bubble: some View {
        let frame = IslandLayout.bubbleFrame(notch: geometry.notch, screenSize: geometry.screenSize)
        let slide = AnyTransition.offset(x: frame.width + IslandLayout.bubbleGap)
            .combined(with: .scale(scale: 0.6)).combined(with: .opacity)
        return ZStack {
            if let content = bubbleContent {
                SideBubble(content: content, diameter: frame.width)
                    .transition(reduceMotion ? .opacity : slide)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Self.spring, value: state.bubbleTab)
    }

    private var bubbleContent: SideBubble.Content? {
        switch state.bubbleTab {
        case .media:
            state.nowPlaying.map {
                .media(front: $0, behind: state.mediaSlots.dropFirst().first?.info)
            }
        case .agents:
            state.board.lead.map { .agent($0) }
        case nil:
            nil
        }
    }
```

- [ ] **Step 5: Hover in `OverlayController`**

Add `private var pointerOnBubble = false` next to `pointerInside`, and:

```swift
    /// The bubble's hover area while there is a bubble.
    private var bubbleHitRect: CGRect? {
        guard let tab = state.bubbleTab else { return nil }
        return IslandLayout.bubbleHitRect(
            notch: geometry.notch, screenSize: geometry.screenSize,
            hasBehind: tab == .media && state.mediaSlots.count > 1)
    }
```

In `pointerMoved`, replace the `inside` line:

```swift
        let local = metrics.localPoint(fromGlobal: point)
        // Read again when the hover fires: the pointer may have moved on to the island.
        pointerOnBubble = bubbleHitRect?.contains(local) ?? false
        let inside = pointerOnBubble || hitRect.contains(local)
```

and the hover call:

```swift
            // Resting on the bubble opens the island on the bubble's tab.
            let tab = inside && self.pointerOnBubble ? self.state.bubbleTab : nil
            self.state.setHovering(inside, opening: tab)
```

In `resetHoverState` also set `pointerOnBubble = false`.

- [ ] **Step 6: Off-screen render**

In `DebugRender.runIfRequested`, after the `collapsed-media-two` write:

```swift
        write(
            BubbleGallery(slots: twoSources.mediaSlots), size: CGSize(width: 380, height: 170),
            named: "collapsed-bubble", to: directory)
```

and the gallery:

```swift
/// The bubble beside the notch: music beside the agents face (one source, two sources),
/// and an agent beside the media face.
private struct BubbleGallery: View {
    let slots: [NowPlayingSlot]

    private var lead: AgentRow {
        var board = AgentSessionBoard()
        board.update([
            AgentSession(
                id: "x", tool: .claudeCode, title: "fix-login-flow", projectPath: nil,
                activity: .working, since: Date(), pid: nil)
        ])
        return board.rows[0]
    }

    private func row(_ bubble: SideBubble.Content, _ face: some View) -> some View {
        HStack(spacing: IslandLayout.bubbleGap) {
            SideBubble(content: bubble, diameter: 28)
            face
                .frame(width: 272, height: 32)
                .background(
                    .black,
                    in: UnevenRoundedRectangle(
                        bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous))
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            row(.media(front: slots[0].info, behind: nil), AgentNotchFace(row: lead, notchWidth: 200))
            row(
                .media(front: slots[0].info, behind: slots[1].info),
                AgentNotchFace(row: lead, notchWidth: 200))
            row(.agent(lead), CollapsedContent(info: slots[0].info, behind: slots[1].info, notchWidth: 200))
        }
        .padding(.leading, 24)
        .padding(16)
    }
}
```

- [ ] **Step 7: Build, render, look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Expected: `** BUILD SUCCEEDED **`; `build/render/collapsed-bubble.png` shows three rows, each a black disc 6 pt left of the notch shape; the second row has a smaller disc behind on the left. Then run live with `SYMBIODOCK_DEMO_AGENTS=working SYMBIODOCK_DEMO_MEDIA=2` and check `swift scripts/list-windows.swift` and `top` (0 % at rest).

- [ ] **Step 8: Commit and push**

```bash
git add Symbiodock docs/superpowers
git commit -m "feat(island): show the second face in a bubble beside the notch"
git push origin main
```

---

### Task 3: Record it

**Files:** Modify `CLAUDE.md` (decision row, `Durum` entry).

- [ ] **Step 1:** Add the `Yan baloncuk` row to the decision table and a `Durum` bullet (test count, what was verified off-screen and live, what waits for the owner).
- [ ] **Step 2:** Run both verification commands; commit `docs: record the side bubble`; push.

---

## Manual checklist (for the owner)

1. `Agents` first, music playing, give an agent a task: the pet takes the left wing and the artwork slides out to a round bubble left of the island.
2. Play Apple Music and a browser video together: a second, smaller disc shows behind the bubble on the left.
3. Make `Media` the first tab (right click → First tab): the artwork stays on the island and the working agent's pet is in the bubble.
4. Rest the pointer on the bubble: the island opens on the bubble's tab. Rest it on the island: it opens on the first tab.
5. When the agent finishes while in the bubble: the Face ID seal plays in the bubble, then the bubble slides back behind the island.
6. Pause the music: 10 s later the bubble (or the wings) goes.
7. Open the island, drag it, dock it at an edge: no bubble in any of these.
8. In an app with many menus: note whether the bubble covers the last menu.
9. Reduce Motion on: the bubble fades in and out without sliding.
10. `top` with the bubble showing: Symbiodock at 0 %.
