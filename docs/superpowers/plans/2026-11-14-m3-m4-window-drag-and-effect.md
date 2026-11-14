# Milestones 3–4, part 2: Dragging, Snapping and the Symbiote Effect on Screen

**Status:** implemented on 2026-11-14 while the owner was away from the Mac, at the owner's request ("do the best you can"). Nothing here has been tried by hand. Every stage of a drag was rendered offscreen from the real code and checked by eye (see "How this was verified").

**Goal:** The island can be grabbed and pulled off its anchor; goo strands stretch and tear; released, it glides to the notch, an edge or a corner and stays there across launches; "Return to notch" brings it back.

**Built on:** `docs/superpowers/plans/2026-11-14-m3-core-drag-and-snap.md` (anchors, `SnapResolver`, floating layout, drag state machine) and spec section 5.6 (`SymbioteSimulation`, `SymbioteCanvas`).

## Design

| Piece | File | Responsibility |
|---|---|---|
| `IslandGeometry` | `Symbiodock/Window/IslandGeometry.swift` | Observable notch, visible frame, screen size. Views follow a Dock or menu bar change without a panel rebuild. |
| `AnchorStore` | `Symbiodock/Window/AnchorStore.swift` | Saves and loads the anchor in `UserDefaults` through `AnchorCodec`. |
| `DragSession` | `Symbiodock/Island/DragSession.swift` | The moving parts of one drag: the island's body (position, size), the root shape, and the `SymbioteSimulation`. Not observable; stepped once per display frame. |
| `DragLayer` | `Symbiodock/Island/DragLayer.swift` | `TimelineView(.animation)` that steps the session and draws its snapshot with `SymbioteCanvas` in a sub-rect around the action. Exists only while dragging or settling. |
| `IslandView` | `Symbiodock/Island/IslandView.swift` | Resting island at any anchor (square against its screen edge, rounded free corners, like the notch), or the `DragLayer`. |
| `FloatingCollapsedContent` | `Symbiodock/Island/FloatingCollapsedContent.swift` | Artwork, title and level bars for a collapsed island away from the notch. |
| `OverlayController` | `Symbiodock/Window/OverlayController.swift` | Recognises drags from raw mouse events, runs the state machine, resolves the anchor on release, schedules the end of settling, persists, haptics. |
| `IslandMenu` | `Symbiodock/App/IslandMenu.swift` | "Return to notch", greyed out while the island is at the notch. |

Decisions:

- **Drags come from a local `NSEvent` monitor, not a SwiftUI gesture.** The view under the pointer is replaced when a drag starts, which would cancel a gesture attached to it. A click becomes a drag after 6 pt of movement, so buttons still take clicks.
- **The island is a plain black body while it is dragged** (no artwork or controls). It keeps its resting size while attached and becomes the 200 × 36 capsule once it tears off.
- **State and effect tear on the same event**: `IslandState.drag(to:)` returning true calls `DragSession.tear()`.
- **Settling ends on a timer** (550 ms), not on an animation callback, so it cannot get lost. A lost mouse-up is caught by the pointer poll (`NSEvent.pressedMouseButtons`). A panel rebuild cancels the drag.
- **The panel accepts mouse events for the whole drag, and gives the display back the moment the island is released.** While it glides into place nothing takes clicks. (An independent review found that holding the panel through the settle could lock every click on the display if a queued drag event arrived after the release; that path is closed three ways: one press starts at most one drag, the settle is not cancelled by a drag that did not begin, and the pointer poll finishes a settle whose timer was lost.)
- **Grabbed off-center, the body closes the gap to the pointer once it tears off**, so the capsule ends up under the pointer and lands where the user aims.
- **On the way to its place the capsule takes that place's outline as it arrives** (the notch's shape at the notch; square against the edge when docked), so nothing pops when the resting island takes over. The old place it was pulled off keeps the docked outline and shrinks toward its edge.
- **Root shape**: pulled off the notch, the goo hangs from the notch rect. Pulled off an edge or corner, it hangs from a copy of the island's old place, which shrinks away after the tear. On a display without a physical notch the stand-in notch shrinks away too.
- **Reaching (added later the same day, owner's request)**: a torn-off island that comes within about 70 pt of an edge, or under the notch, throws strands at it (`ReachResolver` picks the surface, `SymbioteSimulation(reaching: true)` grows the strands, `DragSession.stepReaches` owns them). Released while they hold, the island settles on that surface (`SnapResolver.anchor(forRelease:attachedTo:)`); the strands are soaked back up as it lands. Spec 5.5 and 5.6.
- **Haptics**: `.levelChange` when the island tears off, `.alignment` when its strands catch a surface, `.alignment` when a torn-off island is released without having been caught. (The spec said `.generic` for the tear; research suggested `.levelChange` reads better as a "snap". Either is one line to change.)

## How this was verified

- `swift test --package-path Packages/SymbiodockCore`: 124 tests.
- App build: `** BUILD SUCCEEDED **`, no warnings from our code.
- Offscreen: a scratch SwiftPM harness links the real `SymbiodockCore` and compiles the app's `DragSession.swift` and `SymbioteCanvas.swift` unchanged. It drives a full drag (grab at the notch, pull, tear, carry, release near the left edge, settle; then a second drag from the floating position released before tearing) and writes a PNG per stage. Checked: the goo and bodies draw inside the canvas sub-rect at the right place; the body reaches its target within 0.01 pt by the end of the settle time; a release before tearing returns to the same anchor.
- Reaching, offscreen with the same harness (2026-11-14): approach to the bottom edge frame by frame (feelers, landing, hold), a pull away, a 170 pt slide along the edge (tear and re-catch), release while held; the same toward the left edge; a release out in the open (strands thrown on arrival); a return under the notch; and an island torn sideways over the menu bar and pulled down from it. This found and fixed strands crossing each other when the hold began with the island pressed against the edge, and strands ending in mid-air instead of flat on the surface.
- NOT verified (needs the owner): that mouse events reach the monitor as assumed, the feel of the drag, smoothness at the display's refresh rate, haptics, behaviour over full-screen apps and across Spaces while dragging, the look of the floating capsule's content.

## Manual checklist for the owner

1. Press on the notch (or on the island) and pull down slowly. A black body comes out, joined to the notch by sticky strands that thin as you pull.
2. Let go before about 120 pt. The body snaps back into the notch.
3. Pull past about 120 pt. The strands tear (thin ones first), the halves whip back, the trackpad clicks, and the body becomes a capsule under the pointer.
4. Release near the left edge, the bottom edge, and a corner. Each time the capsule glides to that edge or corner and ends flush against it, looking like a notch on that edge (square where it touches the edge, rounded on the free side; in a corner only the inner corner is rounded), clear of the menu bar and the Dock; the trackpad ticks.
5. Hover the docked island. It expands toward the inside of the screen and shows the track and controls; the buttons work.
6. Drag the docked island again; strands tie it to its old place. Release within about 120 pt of the notch center: it returns to the notch.
7. Dock it at an edge, quit, relaunch. It is still at that edge.
8. Right-click the island and choose "Return to notch". It moves back; the entry is greyed out while it is at the notch.
9. While dragging, CPU use is modest and the motion is smooth; at rest CPU is about 0 %.
10. Click (without moving) the play/pause button on the expanded island. It still reacts to the click and does not start a drag.
11. Dock the island in a corner, let it open under the pointer, press and hold without moving: no strand tears. Pull quickly about 100 pt and let go: nothing looks torn and the island goes back. Repeat at an edge and on the open island at the notch. (A bug hunt found strands tearing early when the open island was grabbed; fixed, never seen by hand.)
12. Turn on "Automatically hide and show the menu bar", then dock the island on the top edge 200–250 pt left of the notch, and try it over a full-screen app too: it must not flicker open and closed, and must not jump down when it opens.
13. Press on the island the instant the pointer reaches it and pull: the body must not flash large and small.

14. Carry the torn-off island slowly toward the bottom edge (or the Dock). About 70 pt away thin feelers shoot out of it, then thicker ones; they land on the edge and spread; the trackpad ticks once when the thick one catches.
15. Pull back up slowly: the strands thin and snap, thin ones first. Move in again: they catch again.
16. With the strands holding, slide along the edge: they lean, tear loose behind the island and new ones catch ahead of it. No strand may cross another or end in mid-air.
17. Let go while the strands hold: the island is pulled in to that edge and the strands disappear into it within half a second. Nothing is left on the edge afterwards.
18. Repeat 14–17 at the left and right edges, at the top edge beside the notch, and under the notch (released there, it returns into the notch).
19. Let go out in the middle of the screen: the island still goes to the nearest edge (it never stays in the open), and throws short strands at the edge as it arrives.
20. Tear the island off the notch sideways along the menu bar, then pull it down: strands tie it to the top edge and none are drawn across the island itself.

To see what the drag code decides while you try this, run in a terminal first:

```bash
log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "drag"'
```

It prints one line per milestone ("drag began", "island tore off", "strands caught a surface", "drag ended", "settled", and a line whenever a lost mouse-up or a lost timer had to be recovered). No track or pointer data is logged.

If a drag ever gets stuck (the body follows nothing, or clicks stop reaching other apps), quit with `pkill -x Symbiodock` and report what you did just before.

## Known gaps

- While the island is carried, its strands are drawn over the Dock or the menu bar only up to the border of the visible frame; on a display where the Dock auto-hides that border is the display edge itself.
- The island cannot be grabbed again during the 550 ms it takes to settle.
- Dragged toward another display, the island stops at the edge of its own.
- The hover delay still lives in `OverlayController`; `HoverDebounce` (tested, in core) is not adopted yet.
