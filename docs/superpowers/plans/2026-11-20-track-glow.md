# Track Glow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the track of a shown source changes (first play included), a line in the cover's colours is drawn from the middle of the collapsed island's rim out to both ends, lights the whole rim for a moment and fades; when music sits in the left bubble, the line runs round the bubble from its top.

**Architecture:** What counts as a track change, the wait for the cover, which surface the light plays on, the timing curve and the line's path are pure code in `SymbiodockCore`, tested with `swift test`. The state keeps no clock: like the finish seal, the view sleeps and reports back. The app draws the line with one Core Animation pass (`strokeStart`/`strokeEnd` + opacity) and, for off-screen renders, as a still SwiftUI drawing.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Core Animation, Swift Testing.

Spec: `docs/superpowers/specs/2026-11-20-track-glow-design.md`.

## Global Constraints

- Minimum macOS 14.0. No new dependencies.
- Interface text in English only; code, identifiers and comments in English.
- `RimLight`, `CompactingRim` and the status mark are not touched.
- Nothing redraws per frame at rest: the motion is a one-shot layer animation, and the view is removed when it is over.
- Trigger: the playing track (title + artist) of a shown source changes; first play counts. Pause/resume, seeking and slot reordering do not.
- Wait: at least 0.4 s after the change; then as soon as a cover is there that differs from the previous track's; at 1.0 s with whatever there is. A further change restarts the wait.
- Surface at the moment it plays: bubble if `bubbleTab == .media`; island rim if `face == .media` and `board.attention == .none`; otherwise it does not play and is not deferred. Only while `phase == .collapsed`.
- Motion: 0.6 s spread (ease-out), 0.3 s hold, 0.6 s fade; 1.5 s in all. Reduce Motion: no spread; 0.3 s rise, 0.6 s hold, 0.6 s fade.
- Line: 1.5 pt, over halos of 3.5 pt (30 %) and 6 pt (12 %); round caps; inside the outline.
- Colour: the cover's `ArtworkTint`, left to right (bottom to top on a vertical strip); white at 85 % without one.

---

### Task 1: Core — track changes, timing, outline, state

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/TrackChangeWatch.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/TrackGlow.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/TrackChangeWatchTests.swift` (new), `TrackGlowTests.swift` (new), `IslandStateTests.swift`

**Interfaces — produces:**
- `NowPlayingSource: Hashable, Sendable` with `init(_ info: NowPlayingInfo)`
- `TrackChange { source: NowPlayingSource; staleArtwork: Data? }`
- `TrackChangeWatch` with `mutating func update(_ slots: [NowPlayingSlot]) -> [TrackChange]`
- `TrackGlowMotion.minimumWait`, `maximumWait`, `spread`, `hold`, `fade`, `duration`, `reach(at:)`, `opacity(at:)`, `stillOpacity(at:)`
- `TrackGlowOutline.island(in:radii:dockedEdges:) -> CGPath`, `TrackGlowOutline.bubble(in:) -> CGPath` (origin top left, y down; the line's middle is where the light starts)
- `TrackGlowSurface { island, bubble }`, `TrackGlow { serial: Int; surface; source }`, `AwaitedTrackGlow { serial: Int; source }`
- `IslandState.awaitedTrackGlow: AwaitedTrackGlow?`, `IslandState.trackGlow: TrackGlow?`, `trackGlowSettled(_ serial: Int)`, `trackGlowWaitElapsed(_ serial: Int)`, `trackGlowEnded(_ serial: Int)`

- [ ] **Step 1: Write the failing tests**

`TrackChangeWatchTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct TrackChangeWatchTests {
    private func slot(
        _ title: String, artist: String = "A", playing: Bool = true, cover: UInt8? = nil,
        bundle: String = "com.apple.Music", origin: NowPlayingOrigin = .system
    ) -> NowPlayingSlot {
        NowPlayingSlot(
            info: NowPlayingInfo(
                title: title, artist: artist, artworkData: cover.map { Data([$0]) },
                isPlaying: playing, sourceName: "App", sourceBundleIdentifier: bundle),
            origin: origin)
    }

    private var music: NowPlayingSource { NowPlayingSource(slot("x").info) }

    @Test func theFirstTrackHeardPlayingIsAChange() {
        var watch = TrackChangeWatch()
        #expect(watch.update([slot("One")]) == [TrackChange(source: music, staleArtwork: nil)])
        #expect(watch.update([slot("One")]).isEmpty)
    }

    @Test func anotherTitleOrArtistIsAChange() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([slot("Two")]).count == 1)
        #expect(watch.update([slot("Two", artist: "B")]).count == 1)
    }

    @Test func pausingAndResumingIsNotAChange() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([slot("One", playing: false)]).isEmpty)
        #expect(watch.update([slot("One")]).isEmpty)
    }

    @Test func aTrackSkippedWhilePausedChangesWhenItPlays() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([slot("Two", playing: false)]).isEmpty)
        #expect(watch.update([slot("Two")]).count == 1)
    }

    @Test func aSourceThatGoesAndReturnsWithItsTrackIsNotAChange() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([]).isEmpty)
        #expect(watch.update([slot("One", origin: .companion)]).isEmpty)
    }

    @Test func eachSourceIsWatchedOnItsOwn() {
        var watch = TrackChangeWatch()
        let stream = slot("Stream", bundle: "com.google.Chrome")
        #expect(watch.update([slot("One"), stream]).count == 2)
        // The slots change places: nothing new plays.
        #expect(watch.update([stream, slot("One")]).isEmpty)
        #expect(watch.update([stream, slot("Two")]) == [TrackChange(source: music, staleArtwork: nil)])
    }

    @Test func theChangeNamesTheCoverThatWasThereBefore() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        // The cover arrives after the title.
        _ = watch.update([slot("One", cover: 1)])
        #expect(watch.update([slot("Two", cover: 1)]) == [TrackChange(source: music, staleArtwork: Data([1]))])
        _ = watch.update([slot("Two", cover: 2)])
        #expect(watch.update([slot("Three", cover: 2)]) == [TrackChange(source: music, staleArtwork: Data([2]))])
    }

    @Test func aTrackWithoutATitleIsNotATrack() {
        var watch = TrackChangeWatch()
        #expect(watch.update([slot("")]).isEmpty)
    }
}
```

`TrackGlowTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import SymbiodockCore

struct TrackGlowTests {
    @Test func theLineReachesItsEndsAsTheSpreadEnds() {
        #expect(TrackGlowMotion.reach(at: -1) == 0)
        #expect(TrackGlowMotion.reach(at: 0) == 0)
        #expect(TrackGlowMotion.reach(at: TrackGlowMotion.spread) == 1)
        #expect(TrackGlowMotion.reach(at: 5) == 1)
    }

    @Test func theSpreadSlowsAsItArrives() {
        let half = TrackGlowMotion.reach(at: TrackGlowMotion.spread / 2)
        #expect(half > 0.8 && half < 1)
        var last = 0.0
        for step in 1...20 {
            let reach = TrackGlowMotion.reach(at: TrackGlowMotion.spread * Double(step) / 20)
            #expect(reach >= last)
            last = reach
        }
    }

    @Test func theLightHoldsThenFadesToNothing() {
        #expect(abs(TrackGlowMotion.duration - 1.5) < 1e-9)
        #expect(TrackGlowMotion.opacity(at: -0.1) == 0)
        #expect(TrackGlowMotion.opacity(at: 0) == 1)
        #expect(TrackGlowMotion.opacity(at: 0.89) == 1)
        let fading = TrackGlowMotion.opacity(at: 1.2)
        #expect(fading > 0 && fading < 1)
        #expect(TrackGlowMotion.opacity(at: TrackGlowMotion.duration) == 0)
        #expect(TrackGlowMotion.opacity(at: 3) == 0)
    }

    @Test func withoutMotionTheLightRisesHoldsAndFades() {
        #expect(TrackGlowMotion.stillOpacity(at: 0) == 0)
        #expect(abs(TrackGlowMotion.stillOpacity(at: 0.15) - 0.5) < 1e-9)
        #expect(TrackGlowMotion.stillOpacity(at: 0.5) == 1)
        #expect(TrackGlowMotion.stillOpacity(at: 1.2) == TrackGlowMotion.opacity(at: 1.2))
        #expect(TrackGlowMotion.stillOpacity(at: TrackGlowMotion.duration) == 0)
    }

    @Test func theWaitForTheCoverIsBounded() {
        #expect(TrackGlowMotion.minimumWait == 0.4)
        #expect(TrackGlowMotion.maximumWait == 1.0)
    }

    // MARK: Outline

    /// The corners of the line once its curves are made of short straight pieces.
    private func points(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.flattened(threshold: 0.01).applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            case .closeSubpath: if let first = points.first { points.append(first) }
            default: break
            }
        }
        return points
    }

    /// The point half way along the line.
    private func middle(of path: CGPath) -> CGPoint {
        let points = points(of: path)
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = lengths.reduce(0, +) / 2
        for (index, length) in lengths.enumerated() {
            if left <= length, length > 0 {
                let (a, b) = (points[index], points[index + 1])
                return CGPoint(x: a.x + (b.x - a.x) * left / length, y: a.y + (b.y - a.y) * left / length)
            }
            left -= length
        }
        return points.last ?? .zero
    }

    private func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 0.05
    }

    private func fills(_ path: CGPath, _ rect: CGRect) -> Bool {
        let box = path.boundingBoxOfPath
        return isClose(box.origin, rect.origin)
            && isClose(CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
    }

    private func outline(_ anchor: IslandAnchor, _ size: CGSize) -> CGPath {
        TrackGlowOutline.island(
            in: CGRect(origin: .zero, size: size),
            radii: IslandLayout.cornerRadii(anchor: anchor, radius: 10),
            dockedEdges: IslandLayout.dockedEdges(anchor: anchor))
    }

    @Test func atTheNotchTheLineStartsUnderTheMiddle() {
        let path = outline(.notch, CGSize(width: 272, height: 34))
        let points = points(of: path)
        #expect(isClose(points.first ?? .zero, CGPoint(x: 272, y: 0)))
        #expect(isClose(points.last ?? .zero, CGPoint(x: 0, y: 0)))
        #expect(isClose(middle(of: path), CGPoint(x: 136, y: 34)))
        #expect(fills(path, CGRect(x: 0, y: 0, width: 272, height: 34)))
    }

    @Test func onAStripTheLineStartsAtTheMiddleOfTheFreeLongEdge() {
        let right = outline(.edge(.right, fraction: 0.5), CGSize(width: 36, height: 170))
        #expect(isClose(middle(of: right), CGPoint(x: 0, y: 85)))
        #expect(isClose(points(of: right).first ?? .zero, CGPoint(x: 36, y: 170)))
        #expect(isClose(points(of: right).last ?? .zero, CGPoint(x: 36, y: 0)))
        let left = outline(.edge(.left, fraction: 0.5), CGSize(width: 36, height: 170))
        #expect(isClose(middle(of: left), CGPoint(x: 36, y: 85)))
    }

    @Test func onACapsuleTheLineStartsAtTheMiddleOfTheFreeLongEdge() {
        let bottom = outline(.edge(.bottom, fraction: 0.5), CGSize(width: 200, height: 36))
        #expect(isClose(middle(of: bottom), CGPoint(x: 100, y: 0)))
        let top = outline(.edge(.top, fraction: 0.5), CGSize(width: 200, height: 36))
        #expect(isClose(middle(of: top), CGPoint(x: 100, y: 36)))
    }

    @Test func inACornerTheLineRunsAlongTheTwoFreeEdges() {
        let path = outline(.corner(.topLeft), CGSize(width: 200, height: 36))
        let points = points(of: path)
        #expect(isClose(points.first ?? .zero, CGPoint(x: 200, y: 0)))
        #expect(isClose(points.last ?? .zero, CGPoint(x: 0, y: 36)))
        // Half way along a line that is mostly the bottom edge.
        #expect(abs(middle(of: path).y - 36) < 0.05)
    }

    @Test func aRadiusLargerThanTheIslandIsCutDown() {
        let path = TrackGlowOutline.island(
            in: CGRect(x: 0, y: 0, width: 40, height: 20),
            radii: IslandCornerRadii(topLeading: 0, topTrailing: 0, bottomLeading: 50, bottomTrailing: 50),
            dockedEdges: [.top])
        #expect(fills(path, CGRect(x: 0, y: 0, width: 40, height: 20)))
    }

    @Test func roundTheBubbleTheLineStartsAtTheTop() {
        let path = TrackGlowOutline.bubble(in: CGRect(x: 0, y: 0, width: 28, height: 28))
        let points = points(of: path)
        #expect(isClose(points.first ?? .zero, CGPoint(x: 14, y: 28)))
        #expect(isClose(points.last ?? .zero, CGPoint(x: 14, y: 28)))
        #expect(isClose(middle(of: path), CGPoint(x: 14, y: 0)))
    }
}
```

`IslandStateTests.swift` — add inside the struct (it already has `agent(_:_:)`):

```swift
    // MARK: Track glow

    private func song(_ title: String, playing: Bool = true, cover: UInt8? = nil) -> NowPlayingInfo {
        NowPlayingInfo(
            title: title, artist: "A", artworkData: cover.map { Data([$0]) }, isPlaying: playing,
            sourceName: "Music", sourceBundleIdentifier: "com.apple.Music")
    }

    /// Plays the light of the track that waits, as the view does once its wait is over.
    private func playAwaitedGlow(_ state: IslandState) {
        guard let serial = state.awaitedTrackGlow?.serial else { return }
        state.trackGlowSettled(serial)
        state.trackGlowWaitElapsed(serial)
    }

    @Test func aNewTrackWaitsForItsCoverThenLightsTheIsland() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        let awaited = state.awaitedTrackGlow
        #expect(awaited != nil)
        #expect(state.trackGlow == nil)

        state.trackGlowSettled(awaited?.serial ?? 0)
        #expect(state.awaitedTrackGlow == nil)
        #expect(state.trackGlow?.surface == .island)
        #expect(state.trackGlow?.source == NowPlayingSource(song("One")))

        state.trackGlowEnded(state.trackGlow?.serial ?? 0)
        #expect(state.trackGlow == nil)
    }

    @Test func withoutACoverTheLightPlaysWhenTheWaitIsOver() {
        let state = IslandState()
        state.setNowPlaying(song("One"))
        let serial = state.awaitedTrackGlow?.serial ?? 0
        state.trackGlowSettled(serial)
        #expect(state.trackGlow == nil)
        state.trackGlowWaitElapsed(serial)
        #expect(state.trackGlow?.surface == .island)
    }

    @Test func theLightWaitsForTheNewCoverNotTheOldOne() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        state.trackGlowEnded(state.trackGlow?.serial ?? 0)

        // The title changes first; the old cover is still there.
        state.setNowPlaying(song("Two", cover: 1))
        state.trackGlowSettled(state.awaitedTrackGlow?.serial ?? 0)
        #expect(state.trackGlow == nil)
        state.setNowPlaying(song("Two", cover: 2))
        #expect(state.trackGlow?.surface == .island)
        #expect(state.awaitedTrackGlow == nil)
    }

    @Test func aCoverThatArrivesBeforeTheShortestWaitDoesNotPlayEarly() {
        let state = IslandState()
        state.setNowPlaying(song("One"))
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.trackGlow == nil)
        #expect(state.awaitedTrackGlow != nil)
    }

    @Test func skippingQuicklyLightsOnlyTheLastTrack() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        let first = state.awaitedTrackGlow?.serial ?? 0
        state.setNowPlaying(song("Two", cover: 2))
        let second = state.awaitedTrackGlow?.serial ?? 0
        #expect(second != first)
        // The first track's wait reports late: nothing plays for it.
        state.trackGlowSettled(first)
        state.trackGlowWaitElapsed(first)
        #expect(state.trackGlow == nil)
        state.trackGlowSettled(second)
        #expect(state.trackGlow?.serial == second)
    }

    @Test func pausingAndResumingLightsNothing() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        state.trackGlowEnded(state.trackGlow?.serial ?? 0)
        state.setNowPlaying(song("One", playing: false, cover: 1))
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.awaitedTrackGlow == nil)
        #expect(state.trackGlow == nil)
    }

    @Test func musicInTheBubbleLightsTheBubble() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.bubbleTab == .media)
        playAwaitedGlow(state)
        #expect(state.trackGlow?.surface == .bubble)
    }

    @Test func anAgentLightOnTheIslandKeepsTheTrackLightAway() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.face == .media)
        playAwaitedGlow(state)
        #expect(state.trackGlow == nil)
        #expect(state.awaitedTrackGlow == nil)
    }

    @Test func noLightWhileTheIslandIsOpenAndNoneLater() {
        let state = IslandState()
        state.setHovering(true)
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        #expect(state.trackGlow == nil)
        state.setHovering(false)
        #expect(state.trackGlow == nil)
        #expect(state.awaitedTrackGlow == nil)
    }

    @Test func noLightWhereTheMusicHasNoFace() {
        let state = IslandState()
        state.restoreAnchor(.edge(.bottom, fraction: 0.5))
        state.setAgentSessions([agent("a", .working)])
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.face == .agents)
        playAwaitedGlow(state)
        #expect(state.trackGlow == nil)
    }

    @Test func aLightThatLosesItsSurfaceGoesOut() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        #expect(state.trackGlow != nil)
        state.setHovering(true)
        #expect(state.trackGlow == nil)

        // On the island, an agent starts to work: the music moves out to the bubble.
        state.setHovering(false)
        state.setNowPlaying(song("Two", cover: 2))
        playAwaitedGlow(state)
        #expect(state.trackGlow?.surface == .island)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.trackGlow == nil)
    }

    @Test func theSecondSourceLightsWithItsOwnTrack() {
        let state = IslandState()
        state.setNowPlaying(
            NowPlayingInfo(
                title: "Stream", artist: "", isPlaying: true, sourceName: "Chrome",
                sourceBundleIdentifier: "com.google.Chrome"))
        playAwaitedGlow(state)
        state.trackGlowEnded(state.trackGlow?.serial ?? 0)
        state.setCompanionPlaying(song("One", cover: 1))
        #expect(state.mediaSlots.count == 2)
        playAwaitedGlow(state)
        #expect(state.trackGlow?.source == NowPlayingSource(song("One")))
    }

    @Test func anEndedLightOfAnotherSerialIsLeftAlone() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        let serial = state.trackGlow?.serial ?? 0
        state.trackGlowEnded(serial - 1)
        #expect(state.trackGlow?.serial == serial)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -20`
Expected: build errors — `cannot find 'TrackChangeWatch' in scope`, `cannot find 'TrackGlowMotion' in scope`, `value of type 'IslandState' has no member 'awaitedTrackGlow'`.

- [ ] **Step 3: Write `TrackChangeWatch.swift`**

```swift
import Foundation

/// Which player a track comes from, however the island heard of it.
public struct NowPlayingSource: Hashable, Sendable {
    public let key: String

    public init(_ info: NowPlayingInfo) {
        key = info.sourceBundleIdentifier ?? info.sourceName
    }
}

/// A track that has just begun on one source.
public struct TrackChange: Equatable, Sendable {
    public let source: NowPlayingSource
    /// The cover the source showed for the track before. The new cover often arrives a moment
    /// after the new title, so a cover equal to this one is not yet the new track's.
    public let staleArtwork: Data?

    public init(source: NowPlayingSource, staleArtwork: Data?) {
        self.source = source
        self.staleArtwork = staleArtwork
    }
}

/// Notices when what a source plays becomes another track.
///
/// A track is its title and artist. Only a track heard playing counts: pausing and resuming
/// changes nothing, and a track skipped to while paused is new once it plays. Each source is
/// remembered for as long as the app runs, so a source that leaves the island and returns
/// with the same track is not new either.
public struct TrackChangeWatch: Sendable {
    private struct Track: Equatable, Sendable {
        let title: String
        let artist: String
    }

    private var lastPlayed: [NowPlayingSource: Track] = [:]
    private var lastArtwork: [NowPlayingSource: Data] = [:]

    public init() {}

    /// Takes what the island shows now and returns the sources whose track is new, in the
    /// order of the slots.
    public mutating func update(_ slots: [NowPlayingSlot]) -> [TrackChange] {
        var changes: [TrackChange] = []
        for slot in slots {
            let info = slot.info
            guard !info.title.isEmpty else { continue }
            let source = NowPlayingSource(info)
            let track = Track(title: info.title, artist: info.artist)
            if info.isPlaying, lastPlayed[source] != track {
                changes.append(TrackChange(source: source, staleArtwork: lastArtwork[source]))
                lastPlayed[source] = track
            }
            // The cover shown with the track last heard is what a later track has to replace.
            if lastPlayed[source] == track { lastArtwork[source] = info.artworkData }
        }
        return changes
    }
}
```

- [ ] **Step 4: Write `TrackGlow.swift`**

```swift
import CoreGraphics
import Foundation

/// Where the light that greets a new track plays.
public enum TrackGlowSurface: Equatable, Sendable {
    /// Along the collapsed island's rim.
    case island
    /// Round the bubble left of the island.
    case bubble
}

/// The light that greets a new track, while it plays.
public struct TrackGlow: Equatable, Sendable {
    /// Goes up with every light, so that each one is a new view and plays once.
    public let serial: Int
    public let surface: TrackGlowSurface
    /// Whose track it greets: its cover gives the colours.
    public let source: NowPlayingSource
}

/// A track that has just changed and waits for its cover before its light plays.
public struct AwaitedTrackGlow: Equatable, Sendable {
    public let serial: Int
    public let source: NowPlayingSource
    let staleArtwork: Data?
    /// The shortest wait is over: the light plays as soon as the new cover is there.
    var isSettled = false
}

/// How the light moves: a line drawn from the middle of the rim out to both ends, lit whole
/// for a moment, then fading.
public enum TrackGlowMotion {
    /// The light never plays sooner after the change than this: the wings settle, and quick
    /// skips become one.
    public static let minimumWait: TimeInterval = 0.4
    /// After this long the light plays with whatever cover there is.
    public static let maximumWait: TimeInterval = 1.0

    public static let spread: TimeInterval = 0.6
    public static let hold: TimeInterval = 0.3
    public static let fade: TimeInterval = 0.6
    public static let duration: TimeInterval = spread + hold + fade

    /// How long the whole line takes to appear when it does not spread (Reduce Motion).
    static let stillRise: TimeInterval = 0.3

    /// How much of each half of the line is drawn `time` seconds in: 0 at the middle, 1 at
    /// the ends. It slows as it arrives.
    public static func reach(at time: TimeInterval) -> Double {
        let progress = min(max(time / spread, 0), 1)
        return 1 - pow(1 - progress, 3)
    }

    /// The light's strength `time` seconds in: full until the hold ends, then falling to
    /// nothing; nothing before it starts and after it is over.
    public static func opacity(at time: TimeInterval) -> Double {
        guard time >= 0, time < duration else { return 0 }
        let fading = (time - spread - hold) / fade
        guard fading > 0 else { return 1 }
        return pow(1 - fading, 2)
    }

    /// The same without the spread: the whole line rises, holds and fades over the same time.
    public static func stillOpacity(at time: TimeInterval) -> Double {
        guard time >= 0, time < duration else { return 0 }
        return min(time / stillRise, 1) * opacity(at: time)
    }
}

/// The line the light is drawn along, as an open path whose middle is where the light starts.
/// The origin is the top left and y runs down, as on screen.
public enum TrackGlowOutline {
    /// The island's rim where it is free of the screen: from the end of one docked edge round
    /// to the start of the next. At the notch that is down the right side, under the notch and
    /// up the left side, so its middle is under the middle of the notch.
    public static func island(
        in rect: CGRect, radii: IslandCornerRadii, dockedEdges: Set<ScreenEdge>
    ) -> CGPath {
        let half = min(rect.width, rect.height) / 2
        // Clockwise as seen on screen, from the top left: edge `i` runs from corner `i` to
        // the next one.
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        let rounding = [radii.topLeading, radii.topTrailing, radii.bottomTrailing, radii.bottomLeading]
            .map { min(max($0, 0), half) }
        let edges: [ScreenEdge] = [.top, .right, .bottom, .left]
        let isFree = edges.map { !dockedEdges.contains($0) }
        let path = CGMutablePath()
        guard isFree.contains(true) else { return path }
        // The line begins with the first free edge after a docked one.
        let start = (0..<4).first { isFree[$0] && !isFree[($0 + 3) % 4] } ?? 0
        let count = (0..<4).prefix { isFree[(start + $0) % 4] }.count
        let isClosed = count == 4

        func point(from a: CGPoint, toward b: CGPoint, by distance: CGFloat) -> CGPoint {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { return a }
            return CGPoint(
                x: a.x + (b.x - a.x) * distance / length, y: a.y + (b.y - a.y) * distance / length)
        }

        path.move(to: point(from: corners[start], toward: corners[(start + 1) % 4], by: rounding[start]))
        for step in 0..<count {
            let edge = (start + step) % 4
            let corner = (edge + 1) % 4
            if step == count - 1, !isClosed {
                // The last free edge ends where the docked one begins.
                path.addLine(to: point(from: corners[corner], toward: corners[edge], by: rounding[corner]))
            } else if rounding[corner] > 0 {
                path.addArc(
                    tangent1End: corners[corner], tangent2End: corners[(corner + 1) % 4],
                    radius: rounding[corner])
            } else {
                path.addLine(to: corners[corner])
            }
        }
        if isClosed { path.closeSubpath() }
        return path
    }

    /// The bubble's rim: a circle that begins and ends at the bottom, so its middle is the top
    /// and the two arms of the light meet below.
    public static func bubble(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        // With y running down, a quarter turn is straight down.
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
            startAngle: .pi / 2, endAngle: .pi / 2 + 2 * .pi, clockwise: false)
        return path
    }
}
```

- [ ] **Step 5: Add the state to `IslandState.swift`**

Give `phase` the extra call in its observer, and add observers to `mediaWings`, `board`, `tabOrder` and `anchor` (each keeps its doc comment and initial value):

```swift
    public private(set) var phase: IslandPhase = .collapsed {
        didSet {
            if phase != .expanded { clearHoveredFile() }
            dropStrayTrackGlow()
        }
    }
```

```swift
    public private(set) var mediaWings = false {
        didSet { dropStrayTrackGlow() }
    }
```

```swift
    public private(set) var board = AgentSessionBoard() {
        didSet { dropStrayTrackGlow() }
    }
```

```swift
    public private(set) var tabOrder: [IslandTab] = TabOrder.default {
        didSet { dropStrayTrackGlow() }
    }
```

```swift
    public private(set) var anchor: IslandAnchor = .notch {
        didSet { dropStrayTrackGlow() }
    }
```

After `retiredOrigins`, add:

```swift
    private var trackWatch = TrackChangeWatch()
    private var trackGlowSerial = 0
    /// A track that has just changed; its light plays once its cover is there or the wait
    /// is over. The view keeps the time (`trackGlowSettled`, `trackGlowWaitElapsed`).
    public private(set) var awaitedTrackGlow: AwaitedTrackGlow?
    /// The light that greets a new track, while it plays; the view reports its end
    /// (`trackGlowEnded`).
    public private(set) var trackGlow: TrackGlow?
```

At the end of `refreshMediaSlots()` (after the `mediaWings` lines), add:

```swift
        noteTrackChanges(in: slots)
```

After `pausedGraceElapsed()`, add:

```swift
    // MARK: Track glow

    /// Where the light of a new track would play now: where the music's face is. Nil when
    /// the music has no face, the island is not collapsed, or an agent's light is on the
    /// island's rim.
    private var trackGlowSurface: TrackGlowSurface? {
        guard phase == .collapsed else { return nil }
        if bubbleTab == .media { return .bubble }
        if face == .media, board.attention == .none { return .island }
        return nil
    }

    /// A new track on a source that is shown starts the wait for its light; a further one
    /// starts it over, so that skipping quickly lights only the last track.
    private func noteTrackChanges(in slots: [NowPlayingSlot]) {
        if let change = trackWatch.update(slots).first {
            trackGlowSerial += 1
            awaitedTrackGlow = AwaitedTrackGlow(
                serial: trackGlowSerial, source: change.source, staleArtwork: change.staleArtwork)
        }
        playAwaitedGlowIfItsCoverIsThere()
    }

    private func playAwaitedGlowIfItsCoverIsThere() {
        guard let awaited = awaitedTrackGlow, awaited.isSettled,
              let slot = mediaSlots.first(where: { NowPlayingSource($0.info) == awaited.source }),
              let artwork = slot.info.artworkData, artwork != awaited.staleArtwork
        else { return }
        playAwaitedGlow()
    }

    /// Plays the light where the music's face is now. Without a face for it, or with its
    /// source gone, the light is dropped, not kept for later.
    private func playAwaitedGlow() {
        guard let awaited = awaitedTrackGlow else { return }
        awaitedTrackGlow = nil
        guard mediaSlots.contains(where: { NowPlayingSource($0.info) == awaited.source }),
              let surface = trackGlowSurface
        else { return }
        trackGlow = TrackGlow(serial: awaited.serial, surface: surface, source: awaited.source)
    }

    /// Called `TrackGlowMotion.minimumWait` after a track changed; ignored for any but the
    /// track that waits now.
    public func trackGlowSettled(_ serial: Int) {
        guard awaitedTrackGlow?.serial == serial else { return }
        awaitedTrackGlow?.isSettled = true
        playAwaitedGlowIfItsCoverIsThere()
    }

    /// Called `TrackGlowMotion.maximumWait` after a track changed: the light plays with
    /// whatever cover there is.
    public func trackGlowWaitElapsed(_ serial: Int) {
        guard awaitedTrackGlow?.serial == serial else { return }
        playAwaitedGlow()
    }

    /// The light has played to its end.
    public func trackGlowEnded(_ serial: Int) {
        if trackGlow?.serial == serial { trackGlow = nil }
    }

    /// A light whose surface is no longer the music's face (the island opened, an agent's
    /// light came on, the music moved to the bubble) goes out and does not come back.
    private func dropStrayTrackGlow() {
        if let glow = trackGlow, glow.surface != trackGlowSurface { trackGlow = nil }
    }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: `Test run with 718 tests in 52 suites passed` (686 + 8 + 11 + 13).

- [ ] **Step 7: Commit and push**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): notice a new track and decide where its light plays"
git push origin main
```

---

### Task 2: App — the line, on the island and round the bubble

**Files:**
- Create: `Symbiodock/Island/TrackGlowLine.swift`
- Modify: `Symbiodock/Island/IslandView.swift`
- Modify: `Symbiodock/Agents/DemoMedia.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`
- Modify: `Symbiodock/App/DebugRender.swift`

**Interfaces — consumes (Task 1):** `IslandState.awaitedTrackGlow`, `trackGlow`, `trackGlowSettled(_:)`, `trackGlowWaitElapsed(_:)`, `trackGlowEnded(_:)`; `TrackGlow.serial/surface/source`; `NowPlayingSource(_:)`; `TrackGlowMotion`; `TrackGlowOutline.island(in:radii:dockedEdges:)`, `.bubble(in:)`. Existing: `ArtworkCache.tint(for:)`, `TintColor.color`, `TintColor.cgColor`, `IslandLayout.dockedEdges(anchor:)`, `IslandLayout.isSideDocked(_:)`.

**Interfaces — produces:** `TrackGlowLine(outline:tint:isVertical:frozenAt:)` with `TrackGlowLine.Outline.island(radii:dockedEdges:)` / `.bubble`.

- [ ] **Step 1: Write `TrackGlowLine.swift`**

```swift
import AppKit
import SwiftUI
import SymbiodockCore

/// The light that greets a new track: a line in the cover's colours, drawn from the middle of
/// the rim out to both ends, lit whole for a moment, then fading (`TrackGlowMotion`). It lies
/// inside the outline it follows. Live it plays once, by Core Animation (`GlowPass`); a view
/// is made for each light and removed when it is over. Still (`frozenAt`, for renders)
/// SwiftUI draws one moment of it.
struct TrackGlowLine: View {
    enum Outline: Equatable {
        /// The collapsed island's rim, less the edges against the screen.
        case island(radii: IslandCornerRadii, dockedEdges: Set<ScreenEdge>)
        /// The bubble beside the island, from its top round both sides.
        case bubble

        /// The line in `bounds`, wholly inside the outline; origin top left, y down.
        @MainActor
        func path(in bounds: CGRect) -> CGPath {
            let inset = TrackGlowLine.lineWidth / 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            switch self {
            case .island(let radii, let dockedEdges):
                func inner(_ radius: CGFloat) -> CGFloat { max(radius - inset, 0) }
                return TrackGlowOutline.island(
                    in: rect,
                    radii: IslandCornerRadii(
                        topLeading: inner(radii.topLeading), topTrailing: inner(radii.topTrailing),
                        bottomLeading: inner(radii.bottomLeading),
                        bottomTrailing: inner(radii.bottomTrailing)),
                    dockedEdges: dockedEdges)
            case .bubble:
                return TrackGlowOutline.bubble(in: rect)
            }
        }
    }

    let outline: Outline
    /// The colours of the cover of the track; nil for none, and the line is white.
    let tint: ArtworkTint?
    /// The island is a vertical strip: the colours run bottom to top, like its bars.
    var isVertical = false
    /// Draws the light as it is this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let lineWidth: CGFloat = 1.5
    /// The halos under the line and the line itself: how wide, and how strong.
    static let strokes: [(width: CGFloat, strength: Double)] = [(6, 0.12), (3.5, 0.30), (lineWidth, 1)]
    /// How strong the white line of a cover without colour is.
    private static let colourlessStrength = 0.85

    var body: some View {
        Group {
            if let frozenAt {
                still(at: frozenAt)
            } else {
                GlowPass(outline: outline, colors: layerColors, isVertical: isVertical, spreads: !reduceMotion)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// At least two colours, for a gradient layer.
    private var layerColors: [CGColor] {
        guard let tint, let first = tint.stops.first else {
            let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Self.colourlessStrength)
            return [white, white]
        }
        return tint.stops.count > 1 ? tint.stops.map(\.cgColor) : [first.cgColor, first.cgColor]
    }

    private var fill: AnyShapeStyle {
        guard let tint, !tint.stops.isEmpty else {
            return AnyShapeStyle(Color.white.opacity(Self.colourlessStrength))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: tint.stops.map(\.color),
                startPoint: isVertical ? .bottom : .leading,
                endPoint: isVertical ? .top : .trailing))
    }

    /// One moment of the light, drawn still. Like the live one it is the colours across the
    /// whole frame, shown through the stroked lines; a gradient on the stroke itself would
    /// squeeze the whole run into however much of the line is drawn.
    private func still(at time: TimeInterval) -> some View {
        let reach = reduceMotion ? 1 : TrackGlowMotion.reach(at: time)
        let strength = reduceMotion ? TrackGlowMotion.stillOpacity(at: time) : TrackGlowMotion.opacity(at: time)
        return GeometryReader { proxy in
            let line = Path(outline.path(in: CGRect(origin: .zero, size: proxy.size)))
                .trimmedPath(from: 0.5 - reach / 2, to: 0.5 + reach / 2)
            Rectangle()
                .fill(fill)
                .mask {
                    ZStack {
                        ForEach(Self.strokes.indices, id: \.self) { index in
                            line.stroke(
                                Color.white.opacity(Self.strokes[index].strength),
                                style: StrokeStyle(lineWidth: Self.strokes[index].width, lineCap: .round))
                        }
                    }
                }
        }
        .opacity(strength)
    }
}

/// The live light: a gradient in the cover's colours, shown through a mask of stroked lines
/// whose two ends Core Animation moves apart from the middle, and whose opacity it then
/// lowers to nothing. The render server plays it; the app does no work per frame (see
/// `LayerAnimation.swift`). It plays once for each view that is made: when the island changes
/// size the line follows, and the light goes on from where it was.
private struct GlowPass: NSViewRepresentable {
    let outline: TrackGlowLine.Outline
    let colors: [CGColor]
    let isVertical: Bool
    /// False with Reduce Motion: the whole line rises and fades, and nothing travels.
    let spreads: Bool

    func makeNSView(context: Context) -> PassView { PassView() }

    func updateNSView(_ view: PassView, context: Context) {
        view.configure(outline: outline, colors: colors, isVertical: isVertical, spreads: spreads)
    }

    static func dismantleNSView(_ view: PassView, coordinator: ()) {
        view.stop()
    }

    final class PassView: NSView {
        private let gradient = CAGradientLayer()
        private let mask = CALayer()
        private let lines: [CAShapeLayer]
        private var outline: TrackGlowLine.Outline?
        private var spreads = true
        /// When the light began, on the gradient's own clock. The animations are added again
        /// when the view returns to its window; starting them from this moment continues
        /// the light instead of starting it over, and a light that is over is not played
        /// again.
        private var began: CFTimeInterval?
        private var isPlaying = false

        override init(frame: NSRect) {
            lines = TrackGlowLine.strokes.map { stroke in
                let line = CAShapeLayer()
                line.fillColor = nil
                line.strokeColor = NSColor.white.withAlphaComponent(stroke.strength).cgColor
                line.lineWidth = stroke.width
                line.lineCap = .round
                return line
            }
            super.init(frame: frame)
            wantsLayer = true
            lines.forEach(mask.addSublayer)
            gradient.mask = mask
            // At rest nothing shows: the light is only its animation.
            gradient.opacity = 0
            layer?.addSublayer(gradient)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(outline: TrackGlowLine.Outline, colors: [CGColor], isVertical: Bool, spreads: Bool) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // A cover that arrives while the light plays changes its colours at once.
            gradient.colors = colors
            // The layer's coordinates run upward from the lower left.
            gradient.startPoint = isVertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
            gradient.endPoint = isVertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
            CATransaction.commit()
            if self.outline != outline {
                self.outline = outline
                needsLayout = true
            }
            if self.spreads != spreads {
                self.spreads = spreads
                stop()
            }
            play()
        }

        /// Takes the light down: no animation is left.
        func stop() {
            gradient.removeAllAnimations()
            lines.forEach { $0.removeAllAnimations() }
            isPlaying = false
        }

        override func layout() {
            super.layout()
            guard let outline else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.frame = bounds
            mask.frame = bounds
            // The outline is made with y running down; the layers' y runs up.
            var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
            let path = outline.path(in: bounds).copy(using: &flip)
            for line in lines {
                line.frame = bounds
                line.path = path
            }
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

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            let scale = window?.backingScaleFactor ?? 2
            lines.forEach { $0.contentsScale = scale }
        }

        private func play() {
            guard window != nil, outline != nil, !isPlaying else { return }
            isPlaying = true
            let now = gradient.convertTime(CACurrentMediaTime(), from: nil)
            let start = began ?? now
            began = start
            // A light that has already gone by is over.
            guard now - start < TrackGlowMotion.duration else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Between the middle and itself there is no line; without the spread it is whole.
            for line in lines {
                line.strokeStart = spreads ? 0.5 : 0
                line.strokeEnd = spreads ? 0.5 : 1
            }
            CATransaction.commit()

            let strength = Self.sampled("opacity", spreads ? TrackGlowMotion.opacity : TrackGlowMotion.stillOpacity)
            strength.beginTime = start
            gradient.add(strength, forKey: "strength")
            guard spreads else { return }
            let from = Self.sampled("strokeStart") { 0.5 * (1 - TrackGlowMotion.reach(at: $0)) }
            let to = Self.sampled("strokeEnd") { 0.5 * (1 + TrackGlowMotion.reach(at: $0)) }
            from.beginTime = start
            to.beginTime = start
            // The line stays whole while the light fades, then the layer's own values (no
            // line) hold, under an opacity of nothing.
            for line in lines {
                line.add(from, forKey: "from")
                line.add(to, forKey: "to")
            }
        }

        /// An animation of `keyPath` through `value` over the light's whole length: 60
        /// samples a second, joined by straight lines.
        private static func sampled(_ keyPath: String, _ value: (TimeInterval) -> Double) -> CAKeyframeAnimation {
            let duration = TrackGlowMotion.duration
            let samples = max(8, Int((duration * 60).rounded()))
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = (0...samples).map { value(duration * Double($0) / Double(samples)) }
            animation.keyTimes = (0...samples).map { NSNumber(value: Double($0) / Double(samples)) }
            animation.calculationMode = .linear
            animation.duration = duration
            return animation
        }
    }
}
```

- [ ] **Step 2: Wire it into `IslandView.swift`**

After the `.task(id: state.sealingID) { ... }` block in `body`, add:

```swift
        // A new track waits a moment for its cover, then its light plays; the state decides
        // when, this only keeps the time. A further track cancels the wait and starts another.
        .task(id: state.awaitedTrackGlow?.serial) {
            guard let serial = state.awaitedTrackGlow?.serial else { return }
            try? await Task.sleep(for: .seconds(TrackGlowMotion.minimumWait))
            guard !Task.isCancelled else { return }
            state.trackGlowSettled(serial)
            try? await Task.sleep(for: .seconds(TrackGlowMotion.maximumWait - TrackGlowMotion.minimumWait))
            guard !Task.isCancelled else { return }
            state.trackGlowWaitElapsed(serial)
        }
        // When the light is over its view goes, so nothing is left at rest.
        .task(id: state.trackGlow?.serial) {
            guard let serial = state.trackGlow?.serial else { return }
            try? await Task.sleep(for: .seconds(TrackGlowMotion.duration + 0.1))
            guard !Task.isCancelled else { return }
            state.trackGlowEnded(serial)
        }
```

In `bubble`, replace the `SideBubble(...)` line and its transition with:

```swift
                SideBubble(content: content, diameter: frame.width)
                    .overlay {
                        if let glow = state.trackGlow, glow.surface == .bubble {
                            TrackGlowLine(outline: .bubble, tint: tint(of: glow))
                                .clipShape(Circle())
                                .id(glow.serial)
                        }
                    }
                    .transition(reduceMotion ? .opacity : slide)
```

In `resting`, after the `CompactingRim` overlay and before `.frame(width: frame.width, height: frame.height)`, add:

```swift
            .overlay {
                if let glow = state.trackGlow, glow.surface == .island {
                    TrackGlowLine(
                        outline: .island(
                            radii: radii, dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor)),
                        tint: tint(of: glow), isVertical: IslandLayout.isSideDocked(state.anchor))
                        .id(glow.serial)
                }
            }
```

Before `content(atNotch:frame:)`, add:

```swift
    /// The colours of the cover of the track the light greets.
    private func tint(of glow: TrackGlow) -> ArtworkTint? {
        let slot = state.mediaSlots.first { NowPlayingSource($0.info) == glow.source }
        return ArtworkCache.tint(for: slot?.info.artworkData)
    }
```

- [ ] **Step 3: A demo that changes track — `DemoMedia.swift` and `AppDelegate.swift`**

In `DemoMedia`'s doc comment, add at its end (wrapped like the lines above it):

```swift
/// With `SYMBIODOCK_DEMO_TRACKS=1` as well (and `SYMBIODOCK_DEMO_MEDIA` 1 or 2), the Music track
/// changes every four seconds, each with another cover: for looking at the light that greets a
/// new track.
```

Add to `DemoMedia`:

```swift
    static var cyclesTracks: Bool {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_TRACKS"] == "1" && !wantsOtherApp
    }

    /// Changes the Music track every four seconds for as long as the app runs.
    static func cycleTracks(on state: IslandState, twoSources: Bool = wantsTwoSources) {
        Task { @MainActor in
            let covers: [[Double]] = [[0.55, 0.7], [0.08], [0.3, 0.45, 0.6], [0, 0.9, 0.78]]
            var number = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                let track = NowPlayingInfo(
                    title: "Demo track \(number)", artist: "Demo",
                    artworkData: cover(covers[number % covers.count]), duration: 226, elapsed: 0,
                    elapsedAt: Date(), isPlaying: true, sourceName: "Music",
                    sourceBundleIdentifier: "com.apple.Music")
                if twoSources {
                    state.setCompanionPlaying(track)
                } else {
                    state.setNowPlaying(track)
                }
                number += 1
            }
        }
    }
```

In `AppDelegate.applicationDidFinishLaunching`, inside `if DemoMedia.requested {`, after `DemoMedia.apply(to: state)`:

```swift
            if DemoMedia.cyclesTracks { DemoMedia.cycleTracks(on: state) }
```

- [ ] **Step 4: An off-screen picture — `DebugRender.swift`**

In `runIfRequested()`, after the `expanded-media-volume` write (where `oneSource` exists), add:

```swift
        write(
            TrackGlowGallery(info: oneSource.mediaSlots[0].info), size: CGSize(width: 760, height: 500),
            named: "track-glow", to: directory)
```

Add at file scope (inside the `#if DEBUG`):

```swift
/// The light that greets a new track at four moments (spreading, arriving, whole, fading): at
/// the notch, round the bubble, on a capsule docked at the bottom and on a strip docked right.
private struct TrackGlowGallery: View {
    let info: NowPlayingInfo

    private static let times: [TimeInterval] = [0.08, 0.25, 0.75, 1.25]

    private var tint: ArtworkTint? { ArtworkCache.tint(for: info.artworkData) }

    private var lead: AgentRow {
        var board = AgentSessionBoard()
        board.update([
            AgentSession(
                id: "x", tool: .claudeCode, title: "fix-login-flow", projectPath: nil,
                activity: .working, since: Date(), pid: nil)
        ])
        return board.rows[0]
    }

    private func island(
        _ anchor: IslandAnchor, _ size: CGSize, at time: TimeInterval, @ViewBuilder face: () -> some View
    ) -> some View {
        let radii = IslandLayout.cornerRadii(anchor: anchor, radius: IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)
        return shape.fill(.black)
            .overlay { face() }
            .overlay {
                TrackGlowLine(
                    outline: .island(radii: radii, dockedEdges: IslandLayout.dockedEdges(anchor: anchor)),
                    tint: tint, isVertical: IslandLayout.isSideDocked(anchor), frozenAt: time)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
    }

    private func notch(at time: TimeInterval) -> some View {
        island(.notch, CGSize(width: 272, height: 32 + IslandLayout.notchLip), at: time) {
            CollapsedContent(info: info, notchWidth: 200)
                .padding(.bottom, IslandLayout.notchLip)
        }
    }

    private func bubble(at time: TimeInterval) -> some View {
        HStack(spacing: IslandLayout.bubbleGap) {
            SideBubble(content: .media(front: info, behind: nil), diameter: 28)
                .overlay {
                    TrackGlowLine(outline: .bubble, tint: tint, frozenAt: time)
                        .clipShape(Circle())
                }
            AgentNotchFace(row: lead, notchWidth: 200)
                .frame(width: 272, height: 32)
                .background(
                    .black,
                    in: UnevenRoundedRectangle(
                        bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.times, id: \.self) { notch(at: $0) }
                ForEach(Self.times, id: \.self) { bubble(at: $0) }
                ForEach([0.25, 0.75], id: \.self) { time in
                    island(.edge(.bottom, fraction: 0.5), IslandLayout.floatingCollapsedSize, at: time) {
                        FloatingCollapsedContent(info: info)
                    }
                }
            }
            ForEach([0.25, 0.75], id: \.self) { time in
                island(.edge(.right, fraction: 0.5), IslandLayout.sideCollapsedSize, at: time) {
                    SideCollapsedContent(info: info)
                }
            }
        }
        .padding(16)
    }
}
```

- [ ] **Step 5: Build, render, look**

```bash
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Expected: `** BUILD SUCCEEDED **`; `build/render/track-glow.png` shows, per notch row: a short line under the middle of the notch, a longer one, the whole rim (both sides and the bottom, none along the top) in red→pink→purple, then the same dimmer. Per bubble row: a short arc at the top of the disc, a longer one, the whole ring, the ring dimmer. The capsule's line starts at the middle of its top edge, the strip's at the middle of its left edge. Read the PNG and check each of these.

- [ ] **Step 6: Run it live**

```bash
pkill -x Symbiodock; open --env SYMBIODOCK_DEMO_MEDIA=1 --env SYMBIODOCK_DEMO_TRACKS=1 build/Build/Products/Debug/Symbiodock.app
sleep 12 && top -l 3 -stats pid,command,cpu | grep Symbiodock
swift scripts/list-windows.swift
pkill -x Symbiodock
```

Expected: the app runs without crashing through three track changes; CPU 0 % between lights (a light may show 1–2 % in one sample). Repeat with `--env SYMBIODOCK_DEMO_AGENTS=working` added (the bubble).

- [ ] **Step 7: Commit and push**

```bash
git add Symbiodock
git commit -m "feat(island): greet a new track with a light from the middle of the rim"
git push origin main
```

---

### Task 3: Record it

**Files:** Modify `CLAUDE.md`.

- [ ] **Step 1:** Add a `Parça ışığı` row to the decision table (after `Kapak renkli çubuklar`): what it is, the owner's words ("ortadan sağa ve sola doğru olsun", "yuvarlak kısmın üstünden olsun onda da"), spec path. Add a `Durum` bullet: test count, what was verified off-screen (`track-glow.png`) and live (demo, CPU), what waits for the owner (the look in motion, real covers, real track changes). Mention `SYMBIODOCK_DEMO_TRACKS=1`.
- [ ] **Step 2:** Run both verification commands from `CLAUDE.md`; commit `docs: record the track light`; push.

---

## Manual checklist (for the owner)

1. Start a song in Apple Music with the island closed: the wings open, then a line in the cover's colours starts under the middle of the notch, runs out to both sides and up the ends, the whole rim is lit for a moment and fades.
2. Next track: the same light in the new cover's colours. Same album: the light comes about a second after the change.
3. Press next five times quickly: one light, for the last track.
4. Pause and resume: no light. Seek within the track: no light.
5. Pause, press next, press play: the light plays.
6. With an agent working and `Agents` the first tab (music in the left bubble), change track: the light starts at the top of the bubble, runs down both sides and meets at the bottom; nothing on the island.
7. With `Media` the first tab and an agent asking a question (amber rim): change track — no track light; the amber light is unchanged.
8. Hover the island open, change track with the buttons: no light, and none when it closes.
9. Dock the island at the right edge and change track: the line starts at the middle of the strip's inner edge and runs up and down. At the bottom edge: from the middle of the top edge.
10. Play a browser video and Apple Music together; change the Music track: the light has the Music cover's colours.
11. A cover in black and white: the light is white.
12. Reduce Motion on: the whole rim fades in and out, nothing travels.
13. `top` while music plays and nothing changes: Symbiodock at 0 %.
14. Without real music: `open --env SYMBIODOCK_DEMO_MEDIA=1 --env SYMBIODOCK_DEMO_TRACKS=1 build/Build/Products/Debug/Symbiodock.app` changes track every four seconds.
