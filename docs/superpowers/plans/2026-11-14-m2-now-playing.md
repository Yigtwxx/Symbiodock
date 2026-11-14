# Milestone 2: Now Playing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The island shows the current track (artwork, title, artist, progress) with working previous / play-pause / next, and shows artwork and level bars beside the notch while collapsed.

**Architecture:** Pure logic (data model, payload parsing, progress maths, provider selection, layout) lives in `SymbiodockCore` and is unit-tested. Two providers sit behind `NowPlayingProvider` in the app target: `MediaRemoteProvider` runs the vendored `mediaremote-adapter` helper through `/usr/bin/perl` and reads its JSON stream; `AppleMusicProvider` talks to Music through Apple Events. `NowPlayingService` picks the first available provider and falls back when one fails. `IslandState` mirrors the current track and the SwiftUI views read it.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, XcodeGen, `mediaremote-adapter` v0.7.7 (BSD-3-Clause, Objective-C, vendored as source).

**Spec:** `docs/superpowers/specs/2026-11-14-symbiodock-v1-design.md`, sections 5.4, 5.7, 5.8, 5.9 ("Music access needed"), 6, 7.

**Spike result (2026-11-14, macOS 27.0.1):** the adapter's `get`, `stream` and `test` commands work; `test` exits 0; artwork arrives as base64 JPEG. `send` has not been tried. A live stream reports `duration` 9223372036854.7754, which must be treated as "no duration".

## Changes after review (2026-11-14)

- F1: island content is clipped to the shape; expanded content is top-aligned.
- F2: helper output is split at byte 0x0A only; the parser takes `Data` (U+2028 in titles).
- F3: no Apple Event after Music posts `Stopped` or quits; 2 s refresh quiet period; terminated apps do not count as running.
- F4: every Music script runs inside `with timeout of 2 seconds`; scripts are compiled once; only the error code is logged.
- F5: state script reads each field in its own `try` and joins with ASCII 31; parser splits on U+001F.
- F6: artwork is fetched again on later refreshes while it is nil.
- F7: `bufferingNewest(1)` streams, cancelled `run()` starts no provider, hidden progress bar without a fraction, `LevelBars` hidden from accessibility, `updates` doc comment.

The code in the repository supersedes the code blocks below where they differ.

## Global Constraints

- Minimum macOS: 14.0. Swift language version: 6.
- `SymbiodockCore` must not import AppKit or SwiftUI.
- All code, identifiers and comments in English. All user-facing text in English, as plain literals.
- Sandbox off. Ad-hoc signing. Bundle identifier `com.yigtwxx.Symbiodock`.
- Symbiodock has no menu bar item. Its menu (`IslandMenu`) opens on a secondary click on the island.
- No third-party dependency other than `mediaremote-adapter`. It is vendored as source under `Vendor/mediaremote-adapter` with its `LICENSE`; it is never linked into the app, only bundled.
- Logging uses `os.Logger`. Raw helper output and raw Apple Event replies are never written to logs.
- Never talk to Music through Apple Events unless Music is already running (a `tell application "Music"` would launch it).
- Island geometry is in panel-local coordinates: origin top-left of the display, y down, points.
- Collapsed island with a track: the notch rect widened by 36 pt on each side. Expanded island: 360 × 150 pt. Hit rect: island frame grown by 4 pt.
- Progress is display-only (no scrubbing).
- Commits: Conventional Commits, title ≤ 72 characters, imperative. After each task, commit and push directly to `main`. No pull requests. Never commit `Symbiodock.xcodeproj`, `build/`, secrets.
- Build command used throughout:
  `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | grep -E "warning:|error:|BUILD" | sort -u`
  Expected: `** BUILD SUCCEEDED **`. One Apple warning from `appintentsmetadataprocessor` is known noise.
- Test command used throughout: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
- The plan's code was written without compiling it. If it does not compile, fix it while keeping behaviour and the listed interfaces, and update this plan in the same commit.

## File Structure

```
Packages/SymbiodockCore/Sources/SymbiodockCore/
  NowPlaying/NowPlayingInfo.swift            NowPlayingInfo, PlaybackCommand, NowPlayingProvider
  NowPlaying/SourceName.swift                bundle identifier → display name
  NowPlaying/MediaRemotePayloadParser.swift  one JSON stream line → NowPlayingInfo?
  NowPlaying/AppleMusicPayloadParser.swift   Music script output → NowPlayingInfo?
  NowPlaying/PlaybackProgress.swift          elapsed time and fraction at a given instant
  NowPlaying/NowPlayingService.swift         provider selection and runtime fallback
  IslandState.swift                          (modify) mirrors the current track
  IslandLayout.swift                         (modify) collapsed wings when a track exists
Packages/SymbiodockCore/Tests/SymbiodockCoreTests/
  MediaRemotePayloadParserTests.swift, SourceNameTests.swift, AppleMusicPayloadParserTests.swift,
  PlaybackProgressTests.swift, NowPlayingServiceTests.swift, IslandStateTests.swift (modify),
  IslandLayoutTests.swift (modify)
Vendor/mediaremote-adapter/                  vendored sources, LICENSE, VENDORED.md
Symbiodock/
  NowPlaying/MediaRemoteProvider.swift       helper process, JSON stream, commands
  NowPlaying/AppleScriptRunner.swift         runs a script on the main actor, maps the consent error
  NowPlaying/AppleMusicProvider.swift        provider + watcher for Music
  NowPlaying/NowPlayingCoordinator.swift     builds providers, runs the service
  Island/ArtworkView.swift, LevelBars.swift, CollapsedContent.swift, ExpandedContent.swift
  Island/IslandView.swift                    (modify)
  Window/OverlayController.swift             (modify) shared state, command callback
  App/AppDelegate.swift, App/IslandMenu.swift (modify)
project.yml                                  (modify) helper targets, usage description
```

---

### Task 1: Now Playing model and MediaRemote payload parsing

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/NowPlayingInfo.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/SourceName.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/MediaRemotePayloadParser.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SourceNameTests.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/MediaRemotePayloadParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct NowPlayingInfo: Equatable, Sendable` with `title: String`, `artist: String`, `album: String?`, `artworkData: Data?`, `duration: TimeInterval?`, `elapsed: TimeInterval?`, `elapsedAt: Date?`, `isPlaying: Bool`, `sourceName: String`, and a memberwise `public init` with defaults `album: nil, artworkData: nil, duration: nil, elapsed: nil, elapsedAt: nil`.
  - `enum PlaybackCommand: Equatable, Sendable { case togglePlayPause, next, previous }`
  - `protocol NowPlayingProvider: Sendable` with `func isAvailable() async -> Bool`, `var updates: AsyncStream<NowPlayingInfo?> { get }`, `func send(_ command: PlaybackCommand) async`
  - `SourceName.displayName(forBundleIdentifier: String) -> String`
  - `MediaRemotePayloadParser.info(fromStreamLine: String) throws -> NowPlayingInfo?`
  - `NowPlayingInfo.maximumPlausibleDuration: TimeInterval` (1 000 000 s)

- [ ] **Step 1: Write the failing tests**

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/SourceNameTests.swift`:

```swift
import Testing
@testable import SymbiodockCore

struct SourceNameTests {
    @Test func knownAppsGetTheirName() {
        #expect(SourceName.displayName(forBundleIdentifier: "com.apple.Music") == "Music")
        #expect(SourceName.displayName(forBundleIdentifier: "com.spotify.client") == "Spotify")
        #expect(SourceName.displayName(forBundleIdentifier: "com.apple.Safari") == "Safari")
    }

    @Test func unknownAppsUseTheLastIdentifierComponent() {
        #expect(SourceName.displayName(forBundleIdentifier: "org.videolan.vlc") == "Vlc")
        #expect(SourceName.displayName(forBundleIdentifier: "") == "Unknown")
    }
}
```

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/MediaRemotePayloadParserTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct MediaRemotePayloadParserTests {
    @Test func fullPayloadBecomesInfo() throws {
        let line = """
        {"type":"data","diff":false,"payload":{"playbackRate":1,"album":"Discovery",\
        "elapsedTime":42.5,"timestamp":"2026-11-14T13:33:56Z","bundleIdentifier":"com.apple.Music",\
        "title":"One More Time","duration":320.0,"artist":"Daft Punk","playing":true}}
        """

        let info = try MediaRemotePayloadParser.info(fromStreamLine: line)

        #expect(info == NowPlayingInfo(
            title: "One More Time", artist: "Daft Punk", album: "Discovery",
            duration: 320, elapsed: 42.5,
            elapsedAt: Date(timeIntervalSince1970: 1_794_663_236),
            isPlaying: true, sourceName: "Music"))
    }

    @Test func emptyPayloadMeansNothingIsPlaying() throws {
        #expect(try MediaRemotePayloadParser.info(
            fromStreamLine: #"{"type":"data","diff":false,"payload":{}}"#) == nil)
    }

    @Test func payloadWithoutATitleMeansNothingIsPlaying() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true,"title":""}}"#
        #expect(try MediaRemotePayloadParser.info(fromStreamLine: line) == nil)
    }

    @Test func liveStreamDurationAndEmptyStringsAreDropped() throws {
        let line = """
        {"type":"data","diff":false,"payload":{"album":"","elapsedTime":1615.4,\
        "bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari",\
        "title":"Live Stream","duration":9223372036854.7754,"artist":"","playing":true}}
        """

        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))

        #expect(info.duration == nil)
        #expect(info.album == nil)
        #expect(info.artist == "")
        #expect(info.elapsedAt == nil)
        #expect(info.sourceName == "Safari")
    }

    @Test func artworkIsDecodedFromBase64() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":false,"title":"T","artworkData":"AQID"}}"#

        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))

        #expect(info.artworkData == Data([1, 2, 3]))
        #expect(!info.isPlaying)
    }

    @Test func malformedLineThrows() {
        #expect(throws: (any Error).self) {
            try MediaRemotePayloadParser.info(fromStreamLine: "not json")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: build FAILS with `cannot find 'SourceName' in scope` (or `MediaRemotePayloadParser`).

- [ ] **Step 3: Write the implementation**

`Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/NowPlayingInfo.swift`:

```swift
import Foundation

/// What is playing right now, independent of where the information came from.
public struct NowPlayingInfo: Equatable, Sendable {
    /// Longer "durations" are sentinels (live streams report about 9.2e12 seconds).
    public static let maximumPlausibleDuration: TimeInterval = 1_000_000

    public var title: String
    public var artist: String
    public var album: String?
    public var artworkData: Data?
    public var duration: TimeInterval?
    /// Playback position at `elapsedAt`.
    public var elapsed: TimeInterval?
    /// When `elapsed` was measured; nil if the source did not say.
    public var elapsedAt: Date?
    public var isPlaying: Bool
    /// "Music", "Spotify", "Safari", ...
    public var sourceName: String

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        artworkData: Data? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        elapsedAt: Date? = nil,
        isPlaying: Bool,
        sourceName: String
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedAt = elapsedAt
        self.isPlaying = isPlaying
        self.sourceName = sourceName
    }
}

public enum PlaybackCommand: Equatable, Sendable {
    case togglePlayPause
    case next
    case previous
}

public protocol NowPlayingProvider: Sendable {
    /// False when the provider cannot work on this system.
    func isAvailable() async -> Bool
    /// Emits the current track, or nil when nothing is playing.
    /// The stream finishing means the provider has failed for good.
    var updates: AsyncStream<NowPlayingInfo?> { get }
    func send(_ command: PlaybackCommand) async
}
```

`Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/SourceName.swift`:

```swift
public enum SourceName {
    private static let known: [String: String] = [
        "com.apple.Music": "Music",
        "com.spotify.client": "Spotify",
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Chrome",
    ]

    public static func displayName(forBundleIdentifier identifier: String) -> String {
        if let name = known[identifier] { return name }
        guard let last = identifier.split(separator: ".").last else { return "Unknown" }
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
```

`Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/MediaRemotePayloadParser.swift`:

```swift
import Foundation

/// Parses one line of `mediaremote-adapter.pl ... stream --no-diff` output.
public enum MediaRemotePayloadParser {
    private struct Envelope: Decodable {
        let payload: Payload
    }

    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let timestamp: String?
        let playing: Bool?
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let artworkData: String?
    }

    /// Returns nil when the line says nothing is playing. Throws on a malformed line.
    public static func info(fromStreamLine line: String) throws -> NowPlayingInfo? {
        let payload = try JSONDecoder().decode(Envelope.self, from: Data(line.utf8)).payload
        guard let title = payload.title, !title.isEmpty else { return nil }

        let duration = payload.duration.flatMap { value in
            value > 0 && value < NowPlayingInfo.maximumPlausibleDuration ? value : nil
        }
        // A browser reports its GPU helper as the player; the parent is the app the user knows.
        let identifier = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier ?? ""

        return NowPlayingInfo(
            title: title,
            artist: payload.artist ?? "",
            album: payload.album.flatMap { $0.isEmpty ? nil : $0 },
            artworkData: payload.artworkData.flatMap { Data(base64Encoded: $0) },
            duration: duration,
            elapsed: payload.elapsedTime,
            elapsedAt: payload.timestamp.flatMap { try? Date($0, strategy: .iso8601) },
            isPlaying: payload.playing ?? false,
            sourceName: SourceName.displayName(forBundleIdentifier: identifier))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: PASS, 22 tests, 0 failures. If `fullPayloadBecomesInfo` fails only on `elapsedAt`, compute the expected value with `try Date("2026-11-14T13:33:56Z", strategy: .iso8601)` in the test instead of the literal.

- [ ] **Step 5: Commit and push**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): add now playing model and MediaRemote payload parser"
git push origin main
```

---

### Task 2: Playback progress and provider selection

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/PlaybackProgress.swift`
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/NowPlayingService.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/PlaybackProgressTests.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/NowPlayingServiceTests.swift`

**Interfaces:**
- Consumes: `NowPlayingInfo`, `PlaybackCommand`, `NowPlayingProvider` (Task 1).
- Produces:
  - `PlaybackProgress.elapsed(for: NowPlayingInfo, at: Date) -> TimeInterval?`
  - `PlaybackProgress.fraction(for: NowPlayingInfo, at: Date) -> Double?`
  - `@MainActor final class NowPlayingService` with `init(providers: [any NowPlayingProvider], onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void)`, `func run() async`, `func send(_ command: PlaybackCommand) async`, `var hasActiveProvider: Bool { get }`

- [ ] **Step 1: Write the failing tests**

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/PlaybackProgressTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct PlaybackProgressTests {
    let measuredAt = Date(timeIntervalSince1970: 1_000)

    func info(elapsed: TimeInterval?, duration: TimeInterval?, playing: Bool, stamped: Bool = true)
        -> NowPlayingInfo
    {
        NowPlayingInfo(
            title: "T", artist: "A", duration: duration, elapsed: elapsed,
            elapsedAt: stamped ? measuredAt : nil, isPlaying: playing, sourceName: "Music")
    }

    @Test func playingTrackAdvancesWithTheClock() {
        let track = info(elapsed: 10, duration: 100, playing: true)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(15)) == 25)
        #expect(PlaybackProgress.fraction(for: track, at: measuredAt.addingTimeInterval(15)) == 0.25)
    }

    @Test func pausedTrackStaysWhereItIs() {
        let track = info(elapsed: 10, duration: 100, playing: false)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(15)) == 10)
    }

    @Test func elapsedIsClampedToTheTrack() {
        let track = info(elapsed: 90, duration: 100, playing: true)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(60)) == 100)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(-500)) == 0)
    }

    @Test func unstampedPositionIsUsedAsIs() {
        let track = info(elapsed: 10, duration: 100, playing: true, stamped: false)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(15)) == 10)
    }

    @Test func missingPositionOrDurationGivesNoFraction() {
        #expect(PlaybackProgress.fraction(
            for: info(elapsed: nil, duration: 100, playing: true), at: measuredAt) == nil)
        #expect(PlaybackProgress.fraction(
            for: info(elapsed: 10, duration: nil, playing: true), at: measuredAt) == nil)
    }
}
```

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/NowPlayingServiceTests.swift`:

```swift
import Testing
@testable import SymbiodockCore

private actor CommandLog {
    private(set) var commands: [PlaybackCommand] = []
    func record(_ command: PlaybackCommand) { commands.append(command) }
}

private struct FakeProvider: NowPlayingProvider {
    let available: Bool
    let updates: AsyncStream<NowPlayingInfo?>
    let log = CommandLog()

    /// A provider whose stream delivers `values` and then ends (a runtime failure).
    static func finishing(available: Bool = true, _ values: [NowPlayingInfo?]) -> FakeProvider {
        FakeProvider(available: available, updates: AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        })
    }

    func isAvailable() async -> Bool { available }
    func send(_ command: PlaybackCommand) async { await log.record(command) }
}

@MainActor
private final class Recorder {
    var updates: [NowPlayingInfo?] = []
}

@MainActor
struct NowPlayingServiceTests {
    let a = NowPlayingInfo(title: "A", artist: "", isPlaying: true, sourceName: "One")
    let b = NowPlayingInfo(title: "B", artist: "", isPlaying: true, sourceName: "Two")

    @Test func firstAvailableProviderIsUsedAndFailureFallsBack() async {
        let recorder = Recorder()
        let service = NowPlayingService(
            providers: [FakeProvider.finishing([a]), FakeProvider.finishing([b])],
            onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [a, nil, b, nil])
    }

    @Test func unavailableProviderIsSkipped() async {
        let recorder = Recorder()
        let service = NowPlayingService(
            providers: [FakeProvider.finishing(available: false, [a]), FakeProvider.finishing([b])],
            onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [b, nil])
    }

    @Test func noProviderMeansNothingIsPlaying() async {
        let recorder = Recorder()
        let service = NowPlayingService(providers: [], onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [nil])
        #expect(!service.hasActiveProvider)
    }

    @Test func repeatedIdenticalUpdatesArePublishedOnce() async {
        let recorder = Recorder()
        let service = NowPlayingService(
            providers: [FakeProvider.finishing([a, a, nil, nil, b])],
            onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [a, nil, b, nil])
    }

    @Test func commandsGoToTheActiveProvider() async {
        let (stream, continuation) = AsyncStream<NowPlayingInfo?>.makeStream()
        let active = FakeProvider(available: true, updates: stream)
        let idle = FakeProvider.finishing([b])
        let service = NowPlayingService(providers: [active, idle], onUpdate: { _ in })

        let running = Task { await service.run() }
        // Wait on the clock, not on a number of yields: choosing a provider hops executors.
        let deadline = ContinuousClock.now + .seconds(5)
        while !service.hasActiveProvider, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(service.hasActiveProvider)

        await service.send(.next)

        #expect(await active.log.commands == [.next])
        #expect(await idle.log.commands.isEmpty)

        running.cancel()
        continuation.finish()
        await running.value
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: build FAILS with `cannot find 'PlaybackProgress' in scope` (or `NowPlayingService`).

- [ ] **Step 3: Write the implementation**

`Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/PlaybackProgress.swift`:

```swift
import Foundation

/// Where playback is at a given instant, derived from the last reported position.
public enum PlaybackProgress {
    public static func elapsed(for info: NowPlayingInfo, at now: Date) -> TimeInterval? {
        guard var elapsed = info.elapsed else { return nil }
        if info.isPlaying, let measuredAt = info.elapsedAt {
            elapsed += now.timeIntervalSince(measuredAt)
        }
        elapsed = max(elapsed, 0)
        if let duration = info.duration {
            elapsed = min(elapsed, duration)
        }
        return elapsed
    }

    /// 0...1, or nil when the position or the duration is unknown.
    public static func fraction(for info: NowPlayingInfo, at now: Date) -> Double? {
        guard let duration = info.duration, duration > 0,
              let elapsed = elapsed(for: info, at: now)
        else { return nil }
        return elapsed / duration
    }
}
```

`Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/NowPlayingService.swift`:

```swift
/// Picks a provider and publishes the current track.
///
/// Providers are tried in order. The first available one is used until its stream
/// ends, which counts as a failure; then the next provider that has not failed is tried.
@MainActor
public final class NowPlayingService {
    private let providers: [any NowPlayingProvider]
    private let onUpdate: @MainActor (NowPlayingInfo?) -> Void
    private var active: (any NowPlayingProvider)?
    private var hasPublished = false
    private var lastPublished: NowPlayingInfo?

    public init(
        providers: [any NowPlayingProvider],
        onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void
    ) {
        self.providers = providers
        self.onUpdate = onUpdate
    }

    public var hasActiveProvider: Bool { active != nil }

    /// Runs until every provider has failed or is unavailable, or the task is cancelled.
    public func run() async {
        var failed: Set<Int> = []
        while !Task.isCancelled {
            var chosen: Int?
            for index in providers.indices where !failed.contains(index) {
                if await providers[index].isAvailable() {
                    chosen = index
                    break
                }
            }
            guard let chosen else { break }

            active = providers[chosen]
            for await info in providers[chosen].updates {
                publish(info)
            }
            active = nil
            failed.insert(chosen)
            publish(nil)
        }
        publish(nil)
    }

    public func send(_ command: PlaybackCommand) async {
        await active?.send(command)
    }

    private func publish(_ info: NowPlayingInfo?) {
        guard !hasPublished || info != lastPublished else { return }
        hasPublished = true
        lastPublished = info
        onUpdate(info)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: PASS, 32 tests, 0 failures.

- [ ] **Step 5: Commit and push**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): add playback progress and provider selection"
git push origin main
```

---

### Task 3: Track in the island state, collapsed wings, shared state

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift`
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandLayout.swift`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandStateTests.swift`
- Modify: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandLayoutTests.swift`
- Modify: `Symbiodock/Island/IslandView.swift`
- Modify: `Symbiodock/Window/OverlayController.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `NowPlayingInfo` (Task 1).
- Produces:
  - `IslandState.nowPlaying: NowPlayingInfo?` (read-only outside), `IslandState.setNowPlaying(_ info: NowPlayingInfo?)`, `IslandState.hasTrack: Bool`
  - `IslandLayout.frame(phase:notch:screenSize:hasTrack:)` and `IslandLayout.hitRect(phase:notch:screenSize:hasTrack:)` — the `hasTrack: Bool` parameter is new and has no default; `IslandLayout.collapsedWingWidth: CGFloat` (36)
  - `OverlayController.init(state: IslandState, contextMenu: NSMenu)`, `OverlayController.refreshPointer()`
  - `AppDelegate` owns one `IslandState` and passes it to `OverlayController`.

- [ ] **Step 1: Update the tests**

In `IslandStateTests.swift`, add inside the struct:

```swift
    @Test func mirrorsTheCurrentTrack() {
        let state = IslandState()
        #expect(!state.hasTrack)

        let track = NowPlayingInfo(title: "T", artist: "A", isPlaying: true, sourceName: "Music")
        state.setNowPlaying(track)
        #expect(state.nowPlaying == track)
        #expect(state.hasTrack)

        state.setNowPlaying(nil)
        #expect(!state.hasTrack)
    }
```

In `IslandLayoutTests.swift`, add `hasTrack: false` as the last argument of every existing `IslandLayout.frame(...)` and `IslandLayout.hitRect(...)` call, then add inside the struct:

```swift
    @Test func collapsedIslandWithATrackGrowsAWingOnEachSide() {
        #expect(IslandLayout.frame(phase: .collapsed, notch: notch, screenSize: screen, hasTrack: true)
            == CGRect(x: 626, y: 0, width: 260, height: 32))
    }

    @Test func collapsedWingsStayOnScreen() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .collapsed, notch: leftNotch, screenSize: screen, hasTrack: true)
            == CGRect(x: 0, y: 0, width: 272, height: 32))
    }

    @Test func expandedIslandIgnoresTheTrack() {
        #expect(IslandLayout.frame(phase: .expanded, notch: notch, screenSize: screen, hasTrack: true)
            == CGRect(x: 576, y: 0, width: 360, height: 150))
    }

    @Test func hitRectFollowsTheWings() {
        #expect(IslandLayout.hitRect(phase: .collapsed, notch: notch, screenSize: screen, hasTrack: true)
            == CGRect(x: 622, y: -4, width: 268, height: 40))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: build FAILS (`extra argument 'hasTrack' in call` or `value of type 'IslandState' has no member 'hasTrack'`).

- [ ] **Step 3: Update the core types**

In `IslandState.swift`, add to `IslandState` below `phase`:

```swift
    public private(set) var nowPlaying: NowPlayingInfo?

    /// True while there is a track to show, playing or paused.
    public var hasTrack: Bool { nowPlaying != nil }
```

and below `setHovering`:

```swift
    public func setNowPlaying(_ info: NowPlayingInfo?) {
        nowPlaying = info
    }
```

Replace the whole of `IslandLayout.swift` with:

```swift
import CoreGraphics

/// Island frames in panel-local coordinates.
public enum IslandLayout {
    public static let expandedSize = CGSize(width: 360, height: 150)
    public static let hitPadding: CGFloat = 4
    /// Width added on each side of the notch while a track is shown collapsed.
    public static let collapsedWingWidth: CGFloat = 36

    public static func frame(
        phase: IslandPhase, notch: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect {
        switch phase {
        case .collapsed:
            guard hasTrack else { return notch }
            return anchored(
                width: notch.width + 2 * collapsedWingWidth, height: notch.height,
                notch: notch, screenSize: screenSize)
        case .expanded:
            return anchored(
                width: max(expandedSize.width, notch.width),
                height: max(expandedSize.height, notch.height),
                notch: notch, screenSize: screenSize)
        }
    }

    /// The area in which the pointer counts as hovering the island.
    public static func hitRect(
        phase: IslandPhase, notch: CGRect, screenSize: CGSize, hasTrack: Bool
    ) -> CGRect {
        frame(phase: phase, notch: notch, screenSize: screenSize, hasTrack: hasTrack)
            .insetBy(dx: -hitPadding, dy: -hitPadding)
    }

    /// A rect of the given size hanging from the top edge, centered on the notch, kept on screen.
    private static func anchored(
        width: CGFloat, height: CGFloat, notch: CGRect, screenSize: CGSize
    ) -> CGRect {
        let maxX = max(screenSize.width - width, 0)
        let x = min(max(notch.midX - width / 2, 0), maxX)
        return CGRect(x: x, y: 0, width: width, height: height)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: PASS, 37 tests, 0 failures.

- [ ] **Step 5: Update the app call sites**

In `Symbiodock/Island/IslandView.swift`, change the frame computation to:

```swift
            let frame = IslandLayout.frame(
                phase: state.phase, notch: notch, screenSize: proxy.size, hasTrack: state.hasTrack)
```

and add `state.hasTrack` to the animation so the wings animate too — replace the `.animation(...)` line with:

```swift
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.phase)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.hasTrack)
```

In `Symbiodock/Window/OverlayController.swift`:

- Replace `private let state = IslandState()` and the existing `init(contextMenu:)` with:

```swift
    private let state: IslandState
    private let contextMenu: NSMenu

    init(state: IslandState, contextMenu: NSMenu) {
        self.state = state
        self.contextMenu = contextMenu
    }
```

  (`private let contextMenu: NSMenu` already exists; keep exactly one declaration.)

- In `pointerMoved(toGlobal:)`, change the hit rect computation to:

```swift
        let hitRect = IslandLayout.hitRect(
            phase: state.phase, notch: notch, screenSize: metrics.frame.size,
            hasTrack: state.hasTrack)
```

- Add this method above `pointerMoved(toGlobal:)`:

```swift
    /// Re-checks the pointer after something other than pointer movement changed the hit rect.
    func refreshPointer() {
        pointerMoved(toGlobal: NSEvent.mouseLocation)
    }
```

Replace the whole of `Symbiodock/App/AppDelegate.swift` with:

```swift
import AppKit
import SymbiodockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private var islandMenu: IslandMenu?
    private var overlayController: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let islandMenu = IslandMenu()
        self.islandMenu = islandMenu

        let overlayController = OverlayController(state: state, contextMenu: islandMenu.menu)
        overlayController.start()
        self.overlayController = overlayController
    }
}
```

- [ ] **Step 6: Build and check**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

Run: `pkill -x Symbiodock; sleep 1; open build/Build/Products/Debug/Symbiodock.app; sleep 3; swift scripts/list-windows.swift`
Expected: a line starting with `layer=27 x=0 y=0`. If `open` fails with error -600 right after `pkill`, run it again.

- [ ] **Step 7: Commit and push**

```bash
git add Packages/SymbiodockCore Symbiodock
git commit -m "feat: mirror the current track in island state and layout"
git push origin main
```

---

### Task 4: Vendor mediaremote-adapter and bundle it

**Files:**
- Create: `Vendor/mediaremote-adapter/` (`src/`, `include/`, `bin/mediaremote-adapter.pl`, `LICENSE`, `VENDORED.md`)
- Modify: `project.yml`
- Modify: `README.md` (new section "Third-party code")
- Modify (regenerated): `Symbiodock/Info.plist`

**Interfaces:**
- Consumes: nothing.
- Produces, inside the built `Symbiodock.app`:
  - `Contents/Frameworks/MediaRemoteAdapter.framework` (with a `MediaRemoteAdapter` binary reachable at the framework's top level)
  - `Contents/Resources/mediaremote-adapter.pl`
  - `Contents/MacOS/MediaRemoteAdapterTestClient`
  - `NSAppleEventsUsageDescription` in `Info.plist` (used by Task 7)

- [ ] **Step 1: Copy the sources**

```bash
TMP=$(mktemp -d)
git clone --depth 1 --branch v0.7.7 https://github.com/ungive/mediaremote-adapter.git "$TMP/mra"
git -C "$TMP/mra" rev-parse HEAD
mkdir -p Vendor/mediaremote-adapter/bin
cp -R "$TMP/mra/src" "$TMP/mra/include" "$TMP/mra/LICENSE" Vendor/mediaremote-adapter/
cp "$TMP/mra/bin/mediaremote-adapter.pl" Vendor/mediaremote-adapter/bin/
rm -rf "$TMP"
```

Expected: the printed commit starts with `e3ff502`. If it does not, stop and report (the tag moved).

Create `Vendor/mediaremote-adapter/VENDORED.md`:

```markdown
# mediaremote-adapter

- Upstream: https://github.com/ungive/mediaremote-adapter
- Version: v0.7.7 (commit e3ff502)
- License: BSD-3-Clause, see `LICENSE`
- Copied: `src/`, `include/`, `bin/mediaremote-adapter.pl`, `LICENSE`. Nothing is modified.

Symbiodock builds the framework and the test client from these sources with Xcode
(see `project.yml`) instead of upstream's CMake build. The framework is bundled with
the app and loaded by `/usr/bin/perl`; the app never links against it.

To update: replace the copied files from a newer tag and change the version above.
```

- [ ] **Step 2: Add the targets to `project.yml`**

Under `targets:`, add these two targets after `Symbiodock`:

```yaml
  MediaRemoteAdapter:
    type: framework
    platform: macOS
    sources:
      - path: Vendor/mediaremote-adapter/src/adapter
      - path: Vendor/mediaremote-adapter/src/private
      - path: Vendor/mediaremote-adapter/src/utility
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yigtwxx.Symbiodock.MediaRemoteAdapter
        GENERATE_INFOPLIST_FILE: YES
        HEADER_SEARCH_PATHS:
          - $(SRCROOT)/Vendor/mediaremote-adapter/include
          - $(SRCROOT)/Vendor/mediaremote-adapter/src
        CLANG_ENABLE_OBJC_ARC: YES
        # perl looks the entry points up by name, so they must stay exported.
        GCC_SYMBOLS_PRIVATE_EXTERN: NO
        GCC_WARN_INHIBIT_ALL_WARNINGS: YES
        DEFINES_MODULE: NO
        SKIP_INSTALL: YES
  MediaRemoteAdapterTestClient:
    type: tool
    platform: macOS
    sources:
      - path: Vendor/mediaremote-adapter/src/test
    dependencies:
      - sdk: MediaPlayer.framework
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yigtwxx.Symbiodock.MediaRemoteAdapterTestClient
        CLANG_ENABLE_OBJC_ARC: YES
        GCC_WARN_INHIBIT_ALL_WARNINGS: YES
        SKIP_INSTALL: YES
```

In the `Symbiodock` target:

- Replace its `sources:` with:

```yaml
    sources:
      - path: Symbiodock
      - path: Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl
        buildPhase: resources
```

- Replace its `dependencies:` with:

```yaml
    dependencies:
      - package: SymbiodockCore
      - target: MediaRemoteAdapter
        embed: true
        link: false
      - target: MediaRemoteAdapterTestClient
        embed: true   # XcodeGen 2.45.4 ignores `copy:` unless embed is true
        link: false
        copy:
          destination: executables
```

- Add to its `info.properties`:

```yaml
        NSAppleEventsUsageDescription: Symbiodock reads the current track from Music and controls playback.
```

- [ ] **Step 3: Build and check the bundle**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

If XcodeGen rejects the `copy:` key or the test client does not land in `Contents/MacOS`, get it there with a Copy Files build phase in whatever way this XcodeGen version supports (for example the target's `copyFiles`), not with a script that runs after code signing. The acceptance checks below are what matters.

```bash
APP=build/Build/Products/Debug/Symbiodock.app
ls "$APP/Contents/Frameworks/MediaRemoteAdapter.framework/MediaRemoteAdapter" \
   "$APP/Contents/Resources/mediaremote-adapter.pl" \
   "$APP/Contents/MacOS/MediaRemoteAdapterTestClient"
codesign --verify --deep --strict "$APP" && echo "signature ok"
otool -L "$APP/Contents/MacOS/Symbiodock" | grep -c MediaRemoteAdapter
plutil -p "$APP/Contents/Info.plist" | grep NSAppleEventsUsageDescription
```

Expected: the three paths are listed; `signature ok`; the `grep -c` prints `0` (the app does not link the framework); the usage description is printed.

- [ ] **Step 4: Run the helper from the bundle**

```bash
APP="$PWD/build/Build/Products/Debug/Symbiodock.app"
/usr/bin/perl "$APP/Contents/Resources/mediaremote-adapter.pl" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" \
  "$APP/Contents/MacOS/MediaRemoteAdapterTestClient" test; echo "exit $?"
/usr/bin/perl "$APP/Contents/Resources/mediaremote-adapter.pl" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" get --no-artwork | cut -c1-200
```

Expected: `exit 0`, then either `null` or a JSON object that starts with `{`. Do not paste the JSON into the report beyond noting which of the two it was.

- [ ] **Step 5: Credit the dependency**

In `README.md`, add before `## License`:

```markdown
## Third-party code

Symbiodock bundles [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
by Jonas van den Berg and contributors, under the BSD 3-Clause License. Its sources and
license are in `Vendor/mediaremote-adapter`.
```

- [ ] **Step 6: Commit and push**

```bash
git add Vendor project.yml Symbiodock/Info.plist README.md
git status --short
git commit -m "feat(app): vendor and bundle mediaremote-adapter"
git push origin main
```

`git status --short` before the commit must not list `Symbiodock.xcodeproj` or `build/`.

---

### Task 5: MediaRemoteProvider and wiring the service to the island

**Files:**
- Create: `Symbiodock/NowPlaying/MediaRemoteProvider.swift`
- Create: `Symbiodock/NowPlaying/NowPlayingCoordinator.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `NowPlayingProvider`, `NowPlayingInfo`, `PlaybackCommand`, `MediaRemotePayloadParser.info(fromStreamLine:)`, `NowPlayingService(providers:onUpdate:)` / `run()` / `send(_:)`, `IslandState.setNowPlaying(_:)`, `OverlayController.refreshPointer()`, the bundle layout from Task 4.
- Produces:
  - `struct MediaRemoteProvider: NowPlayingProvider` with `init(paths: MediaRemoteProvider.Paths)` and `MediaRemoteProvider.Paths.inMainBundle() -> Paths?`
  - `@MainActor final class NowPlayingCoordinator` with `init(onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void)`, `start()`, `stop()`, `send(_ command: PlaybackCommand)`

- [ ] **Step 1: Write the provider**

`Symbiodock/NowPlaying/MediaRemoteProvider.swift`:

```swift
import Foundation
import SymbiodockCore
import os

/// System-wide Now Playing through the bundled mediaremote-adapter helper.
///
/// Since macOS 15.4 only entitled processes may use MediaRemote. `/usr/bin/perl` is one,
/// so the helper framework is loaded into perl and prints JSON to stdout.
struct MediaRemoteProvider: NowPlayingProvider {
    struct Paths: Sendable {
        let script: URL
        let framework: URL
        let testClient: URL

        static func inMainBundle() -> Paths? {
            let bundle = Bundle.main
            guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let framework = bundle.privateFrameworksURL?
                      .appendingPathComponent("MediaRemoteAdapter.framework"),
                  let testClient = bundle.url(forAuxiliaryExecutable: "MediaRemoteAdapterTestClient"),
                  FileManager.default.fileExists(atPath: framework.path)
            else { return nil }
            return Paths(script: script, framework: framework, testClient: testClient)
        }
    }

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let maxRestarts = 3
    private static let logger = Logger(
        subsystem: "com.yigtwxx.Symbiodock", category: "MediaRemoteProvider")

    let paths: Paths

    func isAvailable() async -> Bool {
        await Self.runToExit(arguments: [
            paths.script.path, paths.framework.path, paths.testClient.path, "test",
        ]) == 0
    }

    var updates: AsyncStream<NowPlayingInfo?> {
        let paths = paths
        return AsyncStream { continuation in
            let task = Task.detached {
                await Self.streamLoop(paths: paths, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ command: PlaybackCommand) async {
        // Command IDs from the adapter's README.
        let id = switch command {
        case .togglePlayPause: "2"
        case .next: "4"
        case .previous: "5"
        }
        _ = await Self.runToExit(arguments: [
            paths.script.path, paths.framework.path, "send", id,
        ])
    }

    /// Keeps the helper running. Returns when it has been restarted `maxRestarts` times
    /// without staying up, or when the task is cancelled.
    private static func streamLoop(
        paths: Paths, continuation: AsyncStream<NowPlayingInfo?>.Continuation
    ) async {
        var restarts = 0
        while !Task.isCancelled {
            let startedAt = Date()
            await streamOnce(paths: paths, continuation: continuation)
            if Task.isCancelled { return }

            // A helper that ran for a while was working; start counting again.
            if Date().timeIntervalSince(startedAt) > 60 { restarts = 0 }
            guard restarts < maxRestarts else {
                logger.error("The MediaRemote helper keeps exiting; giving up on it.")
                return
            }
            restarts += 1
            try? await Task.sleep(for: .seconds(1 << (restarts - 1)))  // 1 s, 2 s, 4 s
        }
    }

    private static func streamOnce(
        paths: Paths, continuation: AsyncStream<NowPlayingInfo?>.Continuation
    ) async {
        let process = Process()
        process.executableURL = perl
        process.arguments = [
            paths.script.path, paths.framework.path, "stream", "--no-diff", "--debounce=100",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Could not launch the MediaRemote helper.")
            return
        }

        await withTaskCancellationHandler {
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    do {
                        continuation.yield(try MediaRemotePayloadParser.info(fromStreamLine: line))
                    } catch {
                        // The line itself is never logged: it holds what the user is playing.
                        logger.error("Unreadable line from the MediaRemote helper.")
                    }
                }
            } catch {
                logger.error("Reading from the MediaRemote helper failed.")
            }
        } onCancel: {
            process.terminate()
        }
        process.waitUntilExit()
    }

    /// Runs perl with the given arguments and returns its exit status, or -1 if it did not start.
    private static func runToExit(arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = perl
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
```

- [ ] **Step 2: Write the coordinator**

`Symbiodock/NowPlaying/NowPlayingCoordinator.swift`:

```swift
import Foundation
import SymbiodockCore

/// Builds the providers and keeps the Now Playing service running.
@MainActor
final class NowPlayingCoordinator {
    private let service: NowPlayingService
    private var task: Task<Void, Never>?

    init(onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void) {
        var providers: [any NowPlayingProvider] = []
        if let paths = MediaRemoteProvider.Paths.inMainBundle() {
            providers.append(MediaRemoteProvider(paths: paths))
        }
        service = NowPlayingService(providers: providers, onUpdate: onUpdate)
    }

    func start() {
        guard task == nil else { return }
        task = Task { await service.run() }
    }

    /// Cancelling ends the provider's stream, which terminates the helper process.
    func stop() {
        task?.cancel()
        task = nil
    }

    func send(_ command: PlaybackCommand) {
        Task { await service.send(command) }
    }
}
```

- [ ] **Step 3: Wire it into the delegate**

Replace the whole of `Symbiodock/App/AppDelegate.swift` with:

```swift
import AppKit
import SymbiodockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private var islandMenu: IslandMenu?
    private var overlayController: OverlayController?
    private var nowPlaying: NowPlayingCoordinator?
    private var terminationSignalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationHandler()

        let islandMenu = IslandMenu()
        self.islandMenu = islandMenu

        let overlayController = OverlayController(state: state, contextMenu: islandMenu.menu)
        overlayController.start()
        self.overlayController = overlayController

        let nowPlaying = NowPlayingCoordinator { [weak self] info in
            self?.state.setNowPlaying(info)
            // The collapsed hit rect depends on whether there is a track.
            self?.overlayController?.refreshPointer()
        }
        nowPlaying.start()
        self.nowPlaying = nowPlaying
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Otherwise the perl helper would outlive the app until its next write.
        nowPlaying?.stop()
    }

    /// A plain SIGTERM (`pkill`, `kill`) skips `applicationWillTerminate`, which would leave the
    /// perl helper running. Route it through the normal quit path instead.
    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignalSource = source
    }
}
```

- [ ] **Step 4: Build**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`, no warnings from our code.

- [ ] **Step 5: Launch and check the helper process**

```bash
pkill -x Symbiodock; sleep 1; open build/Build/Products/Debug/Symbiodock.app; sleep 4
pgrep -x Symbiodock
pgrep -fl "mediaremote-adapter.pl" | grep -c "stream"
pkill -x Symbiodock; sleep 2
pgrep -fl "mediaremote-adapter.pl" | grep -c "stream"
open build/Build/Products/Debug/Symbiodock.app
```

Expected: a PID; then `1` (one helper streaming); after quitting, `0` (the helper was terminated with the app); the app is left running. If `open` fails with error -600, run it again.

If the first count is `0`: the provider reported unavailable or the paths were not found. Check Step 3 and Step 4 of Task 4 against the built bundle before changing code.

- [ ] **Step 6: Run the core tests**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: PASS, 37 tests.

- [ ] **Step 7: Commit and push**

```bash
git add Symbiodock
git commit -m "feat(app): read now playing through the MediaRemote helper"
git push origin main
```

---

### Task 6: Collapsed and expanded content with playback controls

**Files:**
- Create: `Symbiodock/Island/ArtworkView.swift`
- Create: `Symbiodock/Island/LevelBars.swift`
- Create: `Symbiodock/Island/CollapsedContent.swift`
- Create: `Symbiodock/Island/ExpandedContent.swift`
- Modify: `Symbiodock/Island/IslandView.swift`
- Modify: `Symbiodock/Window/OverlayController.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `IslandState.nowPlaying` / `hasTrack` / `phase`, `NowPlayingInfo`, `PlaybackCommand`, `PlaybackProgress.fraction(for:at:)`, `IslandLayout.frame(phase:notch:screenSize:hasTrack:)`, `NowPlayingCoordinator.send(_:)`.
- Produces:
  - `IslandView(state: IslandState, notch: CGRect, onCommand: @escaping (PlaybackCommand) -> Void)`
  - `OverlayController.init(state: IslandState, contextMenu: NSMenu, onCommand: @escaping (PlaybackCommand) -> Void)`
  - `ArtworkView(data: Data?, size: CGFloat)`, `LevelBars(isPlaying: Bool)`, `CollapsedContent(info: NowPlayingInfo, notchWidth: CGFloat)`, `ExpandedContent(info: NowPlayingInfo?, topInset: CGFloat, onCommand: (PlaybackCommand) -> Void)`

- [ ] **Step 1: Write the small views**

`Symbiodock/Island/ArtworkView.swift`:

```swift
import AppKit
import SwiftUI

/// Album artwork, or a music glyph when there is none.
struct ArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
```

`Symbiodock/Island/LevelBars.swift`:

```swift
import SwiftUI

/// Four bars that move while something is playing. Decorative: they do not follow the audio.
struct LevelBars: View {
    let isPlaying: Bool

    private static let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]
    private static let phases: [Double] = [0, 1.7, 0.6, 2.9]
    private static let height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2.5, height: Self.height * level(index, at: time))
                }
            }
            .frame(height: Self.height)
        }
    }

    private func level(_ index: Int, at time: TimeInterval) -> CGFloat {
        guard isPlaying else { return 0.25 }
        return 0.35 + 0.65 * abs(sin(time * Self.speeds[index] + Self.phases[index]))
    }
}
```

`Symbiodock/Island/CollapsedContent.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// Artwork in the left wing, level bars in the right wing, nothing over the notch itself.
struct CollapsedContent: View {
    let info: NowPlayingInfo
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(data: info.artworkData, size: 20)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: notchWidth)
            LevelBars(isPlaying: info.isPlaying)
                .frame(maxWidth: .infinity)
        }
    }
}
```

`Symbiodock/Island/ExpandedContent.swift`:

```swift
import SwiftUI
import SymbiodockCore

/// Track details and playback controls, or an idle message.
struct ExpandedContent: View {
    let info: NowPlayingInfo?
    /// Height of the notch; nothing can be shown behind it.
    let topInset: CGFloat
    let onCommand: (PlaybackCommand) -> Void

    var body: some View {
        Group {
            if let info {
                track(info)
            } else {
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.top, topInset)
    }

    private func track(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ArtworkView(data: info.artworkData, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ProgressBar(info: info)
            HStack(spacing: 28) {
                control("backward.fill", label: "Previous", command: .previous)
                control(
                    info.isPlaying ? "pause.fill" : "play.fill",
                    label: info.isPlaying ? "Pause" : "Play",
                    command: .togglePlayPause)
                control("forward.fill", label: "Next", command: .next)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func control(_ symbol: String, label: String, command: PlaybackCommand) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Display-only progress. Ticks once per second, and only while it is on screen.
private struct ProgressBar: View {
    let info: NowPlayingInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = PlaybackProgress.fraction(for: info, at: context.date) ?? 0
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
}
```

- [ ] **Step 2: Replace the island view**

Replace the whole of `Symbiodock/Island/IslandView.swift` with:

```swift
import SwiftUI
import SymbiodockCore

struct IslandView: View {
    let state: IslandState
    let notch: CGRect
    let onCommand: (PlaybackCommand) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = IslandLayout.frame(
                phase: state.phase, notch: notch, screenSize: proxy.size, hasTrack: state.hasTrack)
            let radius: CGFloat = state.phase == .expanded ? 24 : 10

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: 0,
                style: .continuous)
                .fill(.black)
                .overlay { content }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.phase)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.hasTrack)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .expanded:
            ExpandedContent(info: state.nowPlaying, topInset: notch.height, onCommand: onCommand)
                .transition(.opacity)
        case .collapsed:
            if let info = state.nowPlaying {
                CollapsedContent(info: info, notchWidth: notch.width)
                    .transition(.opacity)
            }
        }
    }
}
```

- [ ] **Step 3: Pass the command callback through the controller**

In `Symbiodock/Window/OverlayController.swift`:

- Replace the `state` and `contextMenu` properties and the initializer with:

```swift
    private let state: IslandState
    private let contextMenu: NSMenu
    private let onCommand: (PlaybackCommand) -> Void

    init(
        state: IslandState, contextMenu: NSMenu,
        onCommand: @escaping (PlaybackCommand) -> Void
    ) {
        self.state = state
        self.contextMenu = contextMenu
        self.onCommand = onCommand
    }
```

- In the `IslandHostingView` class at the bottom of the file, add this method:

```swift
    /// A click on a panel that never becomes key would otherwise only "activate" it;
    /// the island's buttons must react to the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
```

- In `rebuildPanel()`, replace the line that creates `hostingView` (keep the
  `hostingView.contextMenu = contextMenu` line that follows it) with:

```swift
        let hostingView = IslandHostingView(
            rootView: IslandView(state: state, notch: notch, onCommand: onCommand))
```

In `Symbiodock/App/AppDelegate.swift`, replace the line that creates the overlay controller with:

```swift
        let overlayController = OverlayController(
            state: state, contextMenu: islandMenu.menu
        ) { [weak self] command in
            self?.nowPlaying?.send(command)
        }
```

- [ ] **Step 4: Build and relaunch**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`, no warnings from our code.

```bash
pkill -x Symbiodock; sleep 1; open build/Build/Products/Debug/Symbiodock.app; sleep 4
pgrep -x Symbiodock && swift scripts/list-windows.swift
pgrep -fl "mediaremote-adapter.pl" | grep -c "stream"
```

Expected: a PID, the `layer=27` line, and `1`. Leave the app running.

- [ ] **Step 5: Commit and push**

```bash
git add Symbiodock
git commit -m "feat(app): show the track and playback controls on the island"
git push origin main
```

---

### Task 7: AppleMusicProvider, consent menu entry, phase close

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/AppleMusicPayloadParser.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AppleMusicPayloadParserTests.swift`
- Create: `Symbiodock/NowPlaying/AppleScriptRunner.swift`
- Create: `Symbiodock/NowPlaying/AppleMusicProvider.swift`
- Modify: `Symbiodock/NowPlaying/NowPlayingCoordinator.swift`
- Modify: `Symbiodock/App/IslandMenu.swift`
- Modify: `Symbiodock/App/AppDelegate.swift`
- Modify: `CLAUDE.md` (sections "Durum", "Yol haritası")
- Modify: `README.md` (section "Status")

**Interfaces:**
- Consumes: `NowPlayingProvider`, `NowPlayingInfo`, `PlaybackCommand`, `NowPlayingService`, `NSAppleEventsUsageDescription` (Task 4).
- Produces:
  - `AppleMusicPayloadParser.info(fromScriptOutput: String, at: Date) -> NowPlayingInfo?`
  - `struct AppleMusicProvider: NowPlayingProvider` with `init(onConsentChange: @escaping @MainActor @Sendable (_ denied: Bool) -> Void)`
  - `NowPlayingCoordinator.init(onUpdate:onMusicAccessChange:)` (the second parameter is `@escaping @MainActor @Sendable (_ denied: Bool) -> Void`)
  - `IslandMenu.setMusicAccessNeeded(_ needed: Bool)`
  - Environment variable `SYMBIODOCK_PROVIDER=applemusic` makes the app use only `AppleMusicProvider` (for verification).

- [ ] **Step 1: Write the failing parser tests**

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/AppleMusicPayloadParserTests.swift`:

```swift
import Foundation
import Testing
@testable import SymbiodockCore

struct AppleMusicPayloadParserTests {
    let now = Date(timeIntervalSince1970: 5_000)

    @Test func playingTrackBecomesInfo() {
        let output = "One More Time\nDaft Punk\nDiscovery\n320.5\n42.25\nplaying"

        #expect(AppleMusicPayloadParser.info(fromScriptOutput: output, at: now) == NowPlayingInfo(
            title: "One More Time", artist: "Daft Punk", album: "Discovery",
            duration: 320.5, elapsed: 42.25, elapsedAt: now,
            isPlaying: true, sourceName: "Music"))
    }

    @Test func pausedTrackIsNotPlaying() {
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "T\nA\n\n100\n5\npaused", at: now)

        #expect(info?.isPlaying == false)
        #expect(info?.album == nil)
    }

    @Test func decimalCommaIsAccepted() {
        // AppleScript formats numbers with the user's locale.
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "T\nA\nB\n320,5\n42,25\nplaying", at: now)

        #expect(info?.duration == 320.5)
        #expect(info?.elapsed == 42.25)
    }

    @Test func stoppedOrMalformedOutputMeansNothingIsPlaying() {
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "stopped", at: now) == nil)
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "", at: now) == nil)
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "\nA\nB\n1\n1\nplaying", at: now) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: build FAILS with `cannot find 'AppleMusicPayloadParser' in scope`.

- [ ] **Step 3: Write the parser**

`Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/AppleMusicPayloadParser.swift`:

```swift
import Foundation

/// Parses the reply of the Music state script: six lines —
/// name, artist, album, duration, player position, player state — or the word "stopped".
public enum AppleMusicPayloadParser {
    public static func info(fromScriptOutput output: String, at now: Date) -> NowPlayingInfo? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count == 6, !lines[0].isEmpty else { return nil }

        return NowPlayingInfo(
            title: lines[0],
            artist: lines[1],
            album: lines[2].isEmpty ? nil : lines[2],
            duration: number(lines[3]).flatMap { $0 > 0 ? $0 : nil },
            elapsed: number(lines[4]),
            elapsedAt: now,
            isPlaying: lines[5] == "playing",
            sourceName: "Music")
    }

    /// AppleScript writes numbers with the user's decimal separator.
    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3`
Expected: PASS, 41 tests, 0 failures.

- [ ] **Step 5: Write the script runner and the provider**

`Symbiodock/NowPlaying/AppleScriptRunner.swift`:

```swift
import Foundation

/// Runs AppleScript on the main actor (NSAppleScript is not thread-safe).
@MainActor
enum AppleScriptRunner {
    enum Failure: Error {
        /// The user has not allowed Symbiodock to control the target app.
        case notPermitted
        case other
    }

    /// errAEEventNotPermitted
    private static let notPermittedCode = -1743

    static func run(_ source: String) -> Result<NSAppleEventDescriptor, Failure> {
        guard let script = NSAppleScript(source: source) else { return .failure(.other) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            return .failure(code == notPermittedCode ? .notPermitted : .other)
        }
        return .success(result)
    }
}
```

`Symbiodock/NowPlaying/AppleMusicProvider.swift`:

```swift
import AppKit
import SymbiodockCore

/// Now Playing for Apple Music through public APIs: a distributed notification for
/// changes, Apple Events for the details, artwork and commands.
struct AppleMusicProvider: NowPlayingProvider {
    static let bundleIdentifier = "com.apple.Music"

    /// Called with true when the user has denied Automation access, false when it works.
    let onConsentChange: @MainActor @Sendable (_ denied: Bool) -> Void

    /// Music must never be launched by us: every script is guarded by this.
    @MainActor
    static var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func isAvailable() async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
        }
    }

    var updates: AsyncStream<NowPlayingInfo?> {
        let onConsentChange = onConsentChange
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let watcher = AppleMusicWatcher(
                    continuation: continuation, onConsentChange: onConsentChange)
                watcher.start()
                // Keeps the watcher alive until the consumer goes away.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                }
                watcher.stop()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ command: PlaybackCommand) async {
        let verb = switch command {
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        await MainActor.run {
            guard Self.isMusicRunning else { return }
            _ = AppleScriptRunner.run("tell application \"Music\" to \(verb)")
        }
    }
}

/// Watches Music and yields its state. Lives on the main actor because of NSAppleScript.
@MainActor
private final class AppleMusicWatcher {
    enum Mode {
        /// Refresh when Music posts `com.apple.Music.playerInfo`.
        case notifications
        /// Refresh once per second while Music is running.
        case polling
    }

    /// Switch to `.polling` if the notification is not delivered on this macOS version.
    private static let mode: Mode = .notifications

    private static let stateScript = """
        tell application "Music"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed \
        & (duration of t) & linefeed & (player position) & linefeed & (player state as text)
        end tell
        """
    private static let artworkScript =
        "tell application \"Music\" to get raw data of artwork 1 of current track"

    private let continuation: AsyncStream<NowPlayingInfo?>.Continuation
    private let onConsentChange: @MainActor @Sendable (Bool) -> Void
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var timer: Timer?
    private var artworkKey: String?
    private var artwork: Data?

    init(
        continuation: AsyncStream<NowPlayingInfo?>.Continuation,
        onConsentChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.continuation = continuation
        self.onConsentChange = onConsentChange
    }

    func start() {
        refresh()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == AppleMusicProvider.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.musicDidQuit() }
        }))

        switch Self.mode {
        case .notifications:
            let center = DistributedNotificationCenter.default()
            observers.append((center, center.addObserver(
                forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }))
        case .polling:
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    /// Never ask a quitting Music for its state: the Apple Event would launch it again.
    private func musicDidQuit() {
        artworkKey = nil
        artwork = nil
        continuation.yield(nil)
    }

    private func refresh() {
        guard AppleMusicProvider.isMusicRunning else {
            continuation.yield(nil)
            return
        }
        switch AppleScriptRunner.run(Self.stateScript) {
        case .failure(.notPermitted):
            onConsentChange(true)
            continuation.yield(nil)
        case .failure(.other):
            continuation.yield(nil)
        case .success(let reply):
            onConsentChange(false)
            guard let output = reply.stringValue,
                  var info = AppleMusicPayloadParser.info(fromScriptOutput: output, at: Date())
            else {
                continuation.yield(nil)
                return
            }
            let key = [info.title, info.artist, info.album ?? ""].joined(separator: "\n")
            if key != artworkKey {
                artworkKey = key
                let data = (try? AppleScriptRunner.run(Self.artworkScript).get())?.data
                artwork = data.flatMap { $0.isEmpty ? nil : $0 }
            }
            info.artworkData = artwork
            continuation.yield(info)
        }
    }
}
```

- [ ] **Step 6: Add the provider to the coordinator**

Replace the initializer of `NowPlayingCoordinator` with:

```swift
    init(
        onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void,
        onMusicAccessChange: @escaping @MainActor @Sendable (_ denied: Bool) -> Void
    ) {
        let appleMusic = AppleMusicProvider(onConsentChange: onMusicAccessChange)
        var providers: [any NowPlayingProvider] = []
        // SYMBIODOCK_PROVIDER=applemusic skips the system-wide source, to verify the fallback.
        let appleMusicOnly =
            ProcessInfo.processInfo.environment["SYMBIODOCK_PROVIDER"] == "applemusic"
        if !appleMusicOnly, let paths = MediaRemoteProvider.Paths.inMainBundle() {
            providers.append(MediaRemoteProvider(paths: paths))
        }
        providers.append(appleMusic)
        service = NowPlayingService(providers: providers, onUpdate: onUpdate)
    }
```

- [ ] **Step 7: Add the entry to the island menu**

Replace the whole of `Symbiodock/App/IslandMenu.swift` with:

```swift
import AppKit

/// The island's context menu, shown on a secondary click.
///
/// Symbiodock is an agent app without a Dock icon or a menu bar item,
/// so this menu is the only way to quit.
@MainActor
final class IslandMenu: NSObject {
    let menu = NSMenu()
    private let musicAccessItem: NSMenuItem
    private let musicAccessSeparator = NSMenuItem.separator()

    override init() {
        musicAccessItem = NSMenuItem(
            title: "Music access needed", action: #selector(openAutomationSettings), keyEquivalent: "")
        super.init()

        musicAccessItem.target = self
        menu.addItem(musicAccessItem)
        menu.addItem(musicAccessSeparator)

        let quit = NSMenuItem(
            title: "Quit Symbiodock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        setMusicAccessNeeded(false)
    }

    /// Shows the entry only while Automation consent for Music is missing.
    func setMusicAccessNeeded(_ needed: Bool) {
        musicAccessItem.isHidden = !needed
        musicAccessSeparator.isHidden = !needed
    }

    @objc private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
```

In `Symbiodock/App/AppDelegate.swift`, replace the creation of `nowPlaying` with:

```swift
        let nowPlaying = NowPlayingCoordinator(
            onUpdate: { [weak self] info in
                self?.state.setNowPlaying(info)
                // The collapsed hit rect depends on whether there is a track.
                self?.overlayController?.refreshPointer()
            },
            onMusicAccessChange: { [weak self] denied in
                self?.islandMenu?.setMusicAccessNeeded(denied)
            })
```

- [ ] **Step 8: Build and relaunch**

Run the build command from Global Constraints. Expected: `** BUILD SUCCEEDED **`, no warnings from our code.

```bash
pkill -x Symbiodock; sleep 1; open build/Build/Products/Debug/Symbiodock.app; sleep 4
pgrep -x Symbiodock && pgrep -fl "mediaremote-adapter.pl" | grep -c "stream"
```

Expected: a PID and `1`. Leave the app running in this default mode.

Do NOT launch the app with `SYMBIODOCK_PROVIDER=applemusic` yourself: with Music running it makes macOS show an Automation consent dialog, which only the owner may answer.

- [ ] **Step 9: Update the project documents**

In `CLAUDE.md` (Turkish file, keep it Turkish):

- Replace the body of `## Durum` with:

```markdown
- Faz 0-3 kodu tamam: çekirdek paket testleriyle; agent uygulama ve ada sağ tık menüsü;
  çentik adası, hover, tıklama geçişi; Now Playing (MediaRemote yardımcı süreci + Apple Music
  yedeği), kapalı adada kapak ve seviye çubukları, açık adada parça bilgisi ve kontroller.
- Sürükleme, symbiote efekti ve girişte başlatma yok. Faz 4 başlamadı.
- Xcode 27.2 ve XcodeGen 2.45.4 kurulu, `xcode-select` ile seçili.
```

- In `## Yol haritası`, tick the `Faz 3` box.

In `README.md`, replace the body of `## Status` with:

```markdown
Early development. The notch island, hover expansion and Now Playing with playback
controls work; dragging and the symbiote effect are not built yet.
```

- [ ] **Step 10: Commit and push**

```bash
git add Packages/SymbiodockCore Symbiodock CLAUDE.md README.md
git commit -m "feat(app): add Apple Music provider and consent menu entry"
git push origin main
```

**Phase boundary.** Faz 3 ends here. Stop and give the owner the manual checklist below. Do not start Faz 4 until the owner confirms.

---

## Manual checklist for the owner (after Task 7)

With the app running normally:

1. Play a song in Apple Music. With the island closed, the artwork appears left of the notch and moving bars right of it.
2. Hover the notch. The island shows artwork, title, artist and a progress bar that advances.
3. Click pause. Music pauses on the first click, the button turns into play, the bars stop.
4. Click next and previous. The track changes and the island follows within about a second.
5. Play something in a browser (for example a video). The island shows it.
6. Quit Music and close the browser tab. The wings disappear and the open island says "Nothing playing".
7. Right-click the island and choose "Quit Symbiodock". In Activity Monitor no `perl` process running `mediaremote-adapter.pl` is left.

Apple Music fallback (asks for permission once):

8. With Music playing, run:
   `pkill -x Symbiodock; open --env SYMBIODOCK_PROVIDER=applemusic build/Build/Products/Debug/Symbiodock.app`
   macOS asks whether Symbiodock may control Music. Allow it. The island shows the track; pause, next and previous work.
9. In System Settings → Privacy & Security → Automation, turn Symbiodock's access to Music off, then run the command from item 8 again. The island's right-click menu shows "Music access needed", and choosing it opens the Automation settings.
10. Turn the access back on and relaunch normally (`pkill -x Symbiodock; open build/Build/Products/Debug/Symbiodock.app`).

If item 8 shows the track only after pausing and resuming, or never follows track changes, the `com.apple.Music.playerInfo` notification is not delivered: switch `AppleMusicWatcher.mode` to `.polling`, rebuild, and record the result in `CLAUDE.md` under "Doğrulanmamış varsayımlar".

## Spec coverage for this plan

| Spec section | Task |
|---|---|
| 5.4 Collapsed at the notch while playing: widened, artwork left, bars right | 3, 6 |
| 5.7 `NowPlayingInfo`, `PlaybackCommand`, `NowPlayingProvider` | 1 |
| 5.7 `MediaRemoteProvider` through `mediaremote-adapter` | 4, 5 |
| 5.7 `AppleMusicProvider` (notification, Apple Events, polling fallback) | 7 |
| 5.7 `NowPlayingService` selection rule and runtime fallback | 2, 5, 7 |
| 5.3 `IslandState` mirrors `NowPlayingInfo?` | 3, 5 |
| 5.8 `CollapsedContent`, `ExpandedContent`, idle message | 6 |
| 5.9 "Music access needed" entry in the island menu | 7 |
| 6 Helper exits → restart with backoff, at most 3 times, then switch | 5 |
| 6 Artwork missing → placeholder glyph | 6 |
| 6 Automation consent denied → menu entry opens the settings pane | 7 |
| 6 No raw helper output or Apple Event replies in logs | 5, 7 |
| 7 Tests: provider selection and fallback, payload parsing | 1, 2, 7 |
| 10 Bundled third-party code has a GPL-compatible license | 4 |

Not in this plan: "Return to notch" and anchors (milestone 3), "Launch at login" (milestone 5).
