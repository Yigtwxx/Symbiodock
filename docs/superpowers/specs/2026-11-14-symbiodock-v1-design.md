# Symbiodock v1 Design

Date: 2026-11-14
Status: architecture approved by the owner; this written spec awaits review.

## 1. Goal

A macOS app that turns the MacBook notch into a living island:

1. The island expands when the pointer hovers over it and collapses when the
   pointer leaves.
2. It shows what is currently playing (artwork, title, artist, progress) and
   offers previous / play-pause / next.
3. The island can be dragged off the notch. While it is pulled, it stretches
   like a symbiote: sticky tendrils thin out and tear at a threshold. Once
   released, it snaps to a screen edge or corner and lives there.

The project is expected to grow after v1 (more widgets), so every unit is
built behind a small interface.

## 2. Scope

### In scope for v1

- One island, on one display.
- Hover expand / collapse.
- Now Playing with playback controls.
- Drag, symbiote stretch-and-tear effect, snapping, return to the notch.
- A menu bar status item with "Return to notch" and "Quit".
- Remembering the last dock position across launches.

### Out of scope for v1

- Any widget other than Now Playing (calendar, battery, file shelf, ...).
- More than one island at a time. When the island leaves the notch, the notch
  stays empty.
- Dragging the island between displays.
- A settings window.
- Scrubbing the progress bar (progress is display-only).
- Mac App Store distribution.

## 3. Platform and constraints

| Item | Decision |
|---|---|
| Language / UI | Swift 6, SwiftUI for views, AppKit for the window |
| Minimum macOS | 14.0 (needed for `@Observable`) |
| Development machine | macOS 27.0.1, Swift 6.4.2 |
| App type | Agent app (`LSUIElement = true`): no Dock icon, no main window |
| Sandbox | Off. Apple Events and the MediaRemote helper do not work in the sandbox |
| Distribution | Outside the App Store |
| Hardware | Apple Silicon and Intel Macs; Macs without a notch get a virtual notch (section 5.2) |

Xcode is required to build, sign and debug the app. At the time of writing
only the Command Line Tools are installed on the development machine, so
installing Xcode is a prerequisite for milestone 0.

## 4. Architecture overview

```
AppDelegate
 ├─ StatusItemController        menu bar item: Return to notch, Quit
 ├─ OverlayController           owns the panel, wires everything together
 │   ├─ OverlayPanel (NSPanel)  full-screen transparent window
 │   ├─ MouseTracker            pointer position → hover / click-through
 │   └─ IslandView (SwiftUI)    root view hosted in the panel
 │       ├─ SymbioteCanvas      blob, tendrils, tear effect
 │       ├─ CollapsedContent
 │       └─ ExpandedContent
 ├─ IslandState (@Observable)   single source of truth
 ├─ DragController              drag gesture → state transitions
 └─ NowPlayingService           picks a provider, publishes current track
     ├─ MediaRemoteProvider
     └─ AppleMusicProvider
```

Pure, UI-free units (unit-tested): `NotchGeometry`, `IslandLayout`,
`SnapResolver`, `SymbioteSimulation`, the provider selection logic in
`NowPlayingService`, and payload parsing in the providers.

## 5. Components

### 5.1 OverlayPanel and OverlayController

- One borderless, non-activating `NSPanel` that covers the full frame of the
  island's display.
- Transparent: `isOpaque = false`, `backgroundColor = .clear`,
  `hasShadow = false`.
- Level above the menu bar so the island can merge with the notch.
- `collectionBehavior`: `.canJoinAllSpaces`, `.fullScreenAuxiliary`,
  `.stationary`, `.ignoresCycle`. The island is visible on every Space and
  over full-screen apps.
- The panel never becomes key or main; it must not steal focus.

Click-through: the panel has `ignoresMouseEvents = true` by default.
`MouseTracker` watches the pointer and sets it to `false` only while the
pointer is inside the island's hit rect or a drag is in progress. Everything
outside the island reaches the app underneath.

`MouseTracker` uses a global + local `NSEvent` mouse-moved monitor. If that
turns out to need a permission on macOS 27, it falls back to polling
`NSEvent.mouseLocation` on a 30 Hz timer. Milestone 1 verifies which one is
used.

### 5.2 NotchGeometry

Input: screen frame, `safeAreaInsets`, `auxiliaryTopLeftArea`,
`auxiliaryTopRightArea` (injected as plain values so it is testable).
Output: the notch rect in screen coordinates.

- Display with a notch: the rect between the two auxiliary areas, with the
  height of the top safe-area inset.
- Display without a notch: a virtual notch, 200 × 32 pt, centered on the top
  edge.

Display choice: the built-in display if it has a notch, otherwise the main
display. On `NSApplication.didChangeScreenParametersNotification` the geometry
is recomputed and the island is re-anchored to its saved position.

### 5.3 IslandState

The single source of truth, `@Observable`, main-actor isolated.

```swift
enum IslandAnchor: Equatable, Codable {
    case notch
    case edge(ScreenEdge, fraction: Double)   // 0...1 along the edge
    case corner(ScreenCorner)
}

enum IslandPhase: Equatable {
    case collapsed
    case expanded
    case stretching      // being dragged, still attached to its anchor
    case detached        // being dragged, torn off
    case settling        // released, animating to the target anchor
}
```

State: `anchor`, `phase`, `dragLocation` (while dragging), and the current
`NowPlayingInfo?` mirrored from `NowPlayingService`.

Transitions:

| From | Event | To |
|---|---|---|
| collapsed | pointer inside hit rect for 80 ms | expanded |
| expanded | pointer outside hit rect for 250 ms | collapsed |
| collapsed / expanded | drag begins on the island | stretching |
| stretching | distance from anchor > tear distance | detached |
| stretching | released | settling → collapsed at the same anchor |
| detached | released | settling → collapsed at the resolved anchor |

The island is always collapsed while it is being dragged.

### 5.4 IslandLayout

A pure function from (anchor, phase, notch rect, visible frame, has track)
to the island frame.

- At the notch, collapsed, nothing playing: exactly the notch rect, so the
  island is invisible.
- At the notch, collapsed, playing: the notch rect widened on both sides. The
  left wing shows the artwork thumbnail, the right wing shows animated level
  bars.
- At the notch, expanded: grows downward and sideways from the notch, about
  360 × 150 pt.
- At an edge or corner: a floating black capsule, 8 pt inside the display's
  `visibleFrame`, so it never covers the menu bar or the system Dock. It stays
  visible even when nothing is playing, because it must remain draggable.
  Expanding grows toward the inside of the screen.

### 5.5 DragController and SnapResolver

`DragController` turns a drag gesture on the island into `IslandState`
transitions and feeds the pointer location to the symbiote simulation.

`SnapResolver` is a pure function from the release point to an anchor:

1. Within the notch capture radius (120 pt from the notch center): `.notch`.
2. Within 80 pt of a corner of the visible frame: that `.corner`.
3. Otherwise: the nearest edge, keeping the position along that edge as
   `fraction`.

The resolved anchor is saved to `UserDefaults` and restored at launch.

### 5.6 Symbiote effect

Two parts: a simulation and a renderer.

`SymbioteSimulation` (pure, deterministic, no UI):

- Input per step: root point (where the island was attached), island point
  (where it is now), `dt`.
- It keeps a small set of tendrils. Each tendril is a chain of 5 particles
  between an attachment point on the root and one on the island. Particles
  follow their rest positions with spring lag, so the chain trails and wobbles.
- Particle radius shrinks as the distance grows:
  `radius = baseRadius * (1 - distance / tearDistance)`, clamped at a minimum.
  The neck gets thinner the further the island is pulled.
- Tear distance: 120 pt. When it is exceeded, `isTorn` becomes true and each
  chain splits in the middle: one half retracts into the root, the other half
  into the island, both with a spring.
- Output: a list of circles (center, radius) and `isTorn`.

`SymbioteCanvas` (SwiftUI `Canvas`):

- Draws the root blob, the island body and the tendril circles in black, then
  applies `.alphaThreshold` on top of `.blur`. This is the metaball technique:
  nearby shapes fuse into one sticky silhouette.
- At the notch the root blob is the notch rect itself, so the tendrils merge
  with the physical notch. At an edge or corner the root is a temporary blob
  at the old position that shrinks to nothing after the tear.
- Driven by `TimelineView(.animation)` only in the `stretching`, `detached` and
  `settling` phases. In `collapsed` and `expanded` the island is a plain static
  shape and no per-frame work runs.
- Track content (artwork, bars) is ordinary SwiftUI drawn above the blob layer.

If `Canvas` cannot hold the display's refresh rate or the tendrils do not look
organic enough, the renderer is replaced by a Metal shader. The simulation and
its output format stay the same, so only `SymbioteCanvas` changes.

### 5.7 Now Playing

```swift
struct NowPlayingInfo: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String?
    var artworkData: Data?
    var duration: TimeInterval?
    var elapsed: TimeInterval?
    var isPlaying: Bool
    var sourceName: String        // "Music", "Spotify", "Safari", ...
}

enum PlaybackCommand { case togglePlayPause, next, previous }

protocol NowPlayingProvider: Sendable {
    /// False when the provider cannot work on this system.
    func isAvailable() async -> Bool
    /// Emits the current track, or nil when nothing is playing.
    var updates: AsyncStream<NowPlayingInfo?> { get }
    func send(_ command: PlaybackCommand) async
}
```

Two providers ship in v1 behind this protocol (the owner chose the
"both sources behind one interface" approach, because the app is meant to be
general and Apple restricts system-wide Now Playing data):

`MediaRemoteProvider` — system-wide, covers every app including browsers.
Since macOS 15.4 the private MediaRemote framework only answers entitled
processes, so this provider goes through the open-source
`mediaremote-adapter` helper, which is reported to work by loading the
framework from a system binary that is still allowed to use it, and streams
the result as JSON. Neither that mechanism nor its behaviour on macOS 27 has
been verified for this project yet. Its license must be checked before it is
bundled.

`AppleMusicProvider` — Apple Music only, public APIs. Track changes come from
the `com.apple.Music.playerInfo` distributed notification; artwork and
commands go through Apple Events. This needs `NSAppleEventsUsageDescription`
and the user's Automation consent. If the notification is not delivered on
macOS 27, the provider polls Music through Apple Events once per second while
Music is running.

`NowPlayingService` selection rule:

1. At launch, ask `MediaRemoteProvider.isAvailable()`. If true, use it.
2. Otherwise use `AppleMusicProvider`.
3. If the active provider fails at runtime, switch to the other one.

Milestone 2 starts with a spike that checks `mediaremote-adapter` on
macOS 27. If it does not work, v1 ships with `AppleMusicProvider` only and the
protocol stays in place for later sources (for example a Spotify provider).

### 5.8 Views

- `CollapsedContent`: artwork thumbnail and animated level bars. Hidden when
  nothing is playing.
- `ExpandedContent`: artwork, title, artist, progress bar, and previous /
  play-pause / next buttons. When nothing is playing it shows a short idle
  message.

### 5.9 StatusItemController

A menu bar item with two permanent entries: "Return to notch" (sets the anchor
to `.notch`) and "Quit". An agent app has no other way to quit. A third entry,
"Music access needed", appears only while Automation consent is missing
(section 6).

## 6. Error handling

| Situation | Behaviour |
|---|---|
| Nothing is playing | Idle state; at the notch the island is invisible |
| Automation consent denied | `AppleMusicProvider` reports unavailable; the status menu shows a "Music access needed" entry that opens the Automation settings pane |
| MediaRemote helper exits | Restart with backoff, at most 3 times, then switch provider |
| Artwork missing | Placeholder music glyph |
| Display configuration changes | Recompute geometry, re-anchor to the saved anchor |
| Saved anchor cannot be decoded | Fall back to `.notch` |

Logging uses `os.Logger`. Raw helper output and raw Apple Event replies are
not written to logs.

## 7. Testing

Unit tests for the pure units:

- `NotchGeometry`: notch display, no-notch display.
- `IslandLayout`: every anchor × phase combination, with and without a track.
- `SnapResolver`: notch capture, each corner, each edge, boundary distances.
- `SymbioteSimulation`: tears exactly past the tear distance, radius shrinks
  monotonically with distance, deterministic for a fixed input sequence.
- `NowPlayingService`: provider selection and runtime fallback with fake
  providers.
- Provider payload parsing with recorded sample payloads.

Manual verification, per milestone, by running the app: window level and
click-through, hover timing, behaviour over full-screen apps and across
Spaces, drag and snap, the visual quality of the effect, and CPU use while
idle.

## 8. Milestones

Each milestone ends with working software, and is committed and pushed in
small pieces.

| # | Milestone | Done when |
|---|---|---|
| 0 | Project skeleton | Xcode project builds; agent app launches; status item can quit it |
| 1 | Notch island | Panel sits on the notch; hover expands and collapses with placeholder content; clicks outside the island pass through |
| 2 | Now Playing | MediaRemote spike result recorded; real track data and working controls from at least Apple Music |
| 3 | Drag and snap | Island can be dragged off, snaps to edges and corners, returns to the notch, position survives relaunch |
| 4 | Symbiote effect | Stretch, thinning tendrils, tear and retract, from the notch and from any edge |

Implementation plans are written per milestone, because milestone 2 depends
on a spike result. The first plan covers milestones 0 and 1.

## 9. Risks

| Risk | Mitigation |
|---|---|
| `mediaremote-adapter` does not work on macOS 27 | Spike first; `AppleMusicProvider` is the fallback and is enough for the owner's own use |
| A future macOS update breaks the adapter | Runtime fallback in `NowPlayingService` |
| Click-through via `ignoresMouseEvents` toggling feels laggy at the island's edge | Hit rect is the island frame grown by 4 pt; polling fallback at 30 Hz |
| `Canvas` metaball performance on a full-screen panel | Effect runs only while dragging; Metal renderer as replacement |
| Overlay above the menu bar interferes with menu bar clicks | Panel ignores mouse events everywhere outside the island |

## 10. License

MIT. See `LICENSE` in the repository root.
