# Side Docking and Platform Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** An island docked on the left or right edge becomes a vertical strip (platform icon, rotated title, level bars) that opens sideways on hover.

**Architecture:** `IslandLayout` gives a side-docked, collapsed island a 36 × 170 frame; hover, drag and settle already follow whatever frame the layout returns. The platform is carried on `NowPlayingInfo` (`sourceBundleIdentifier`, `site`); a main-actor `SiteResolver` between the service and the state fills in `site` by asking the browser for its tabs.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Testing, NSAppleScript, `AEDeterminePermissionToAutomateTarget`.

Spec: `docs/superpowers/specs/2026-11-14-side-docking-design.md`.

## Global Constraints

- Minimum macOS 14.0; Swift 6 strict concurrency.
- No new third-party dependency. Logos are Simple Icons SVG files (CC0), listed in `ThirdPartyNotices.txt`.
- UI text is English only.
- Tab URLs and titles are never logged or stored.
- Corners and the top/bottom edges keep the horizontal island.
- After every task: `swift test --package-path Packages/SymbiodockCore` passes and the app builds; commit and push to `main`.

---

### Task 1: Side-docked frame (core)

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandLayout.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandLayoutTests.swift`

**Interfaces — produces:**
- `IslandLayout.sideCollapsedSize: CGSize` = 36 × 170
- `IslandLayout.isSideDocked(_ anchor: IslandAnchor) -> Bool`

- [x] **Step 1: Failing tests** (append to `IslandLayoutTests`, using its `floating(_:_:hasTrack:)` helper; `visible` is `(0, 38, 1512, 880)`)

```swift
// MARK: Side docking

@Test func onlyLeftAndRightEdgesAreSideDocked() {
    #expect(IslandLayout.isSideDocked(.edge(.left, fraction: 0.5)))
    #expect(IslandLayout.isSideDocked(.edge(.right, fraction: 0.2)))
    for anchor in [IslandAnchor.notch, .edge(.top, fraction: 0.5), .edge(.bottom, fraction: 0.5),
                   .corner(.topLeft), .corner(.bottomRight)] {
        #expect(!IslandLayout.isSideDocked(anchor), "\(anchor)")
    }
}

@Test func sideDockedIslandIsAVerticalStripFlushWithItsEdge() {
    let left = floating(.edge(.left, fraction: 0.5))
    #expect(left.size == IslandLayout.sideCollapsedSize)
    #expect(left.minX == visible.minX)
    #expect(abs(left.midY - visible.midY) < 1e-9)

    let right = floating(.edge(.right, fraction: 0.5))
    #expect(right.size == IslandLayout.sideCollapsedSize)
    #expect(right.maxX == visible.maxX)
}

@Test func sideStripOpensSidewaysAroundTheSameCenter() {
    let collapsed = floating(.edge(.right, fraction: 0.4))
    let expanded = floating(.edge(.right, fraction: 0.4), .expanded)
    #expect(expanded.width == IslandLayout.expandedSize.width)
    #expect(expanded.maxX == visible.maxX)
    #expect(abs(expanded.midY - collapsed.midY) < 1e-9)
}

@Test func sideStripStaysInsideTheVisibleFrame() {
    #expect(floating(.edge(.left, fraction: 0)).minY == visible.minY)
    #expect(floating(.edge(.left, fraction: 1)).maxY == visible.maxY)
}

@Test func cornersAndHorizontalEdgesKeepTheHorizontalIsland() {
    for anchor in [IslandAnchor.edge(.top, fraction: 0.5), .edge(.bottom, fraction: 0.5),
                   .corner(.topLeft), .corner(.bottomRight)] {
        #expect(floating(anchor).size == IslandLayout.floatingCollapsedSize, "\(anchor)")
    }
}
```

- [x] **Step 2:** `swift test --package-path Packages/SymbiodockCore --filter IslandLayoutTests` → fails to compile (`sideCollapsedSize` missing).
- [x] **Step 3: Implement.** Add the constant and `isSideDocked`; in `frame(anchor:…)` replace `place(isExpanded ? expandedSize : floatingCollapsedSize)` with `place(isExpanded ? expandedSize : collapsedSize(at: anchor))`, where `collapsedSize(at:)` returns `sideCollapsedSize` when side-docked. The expanded size on a side edge is 540 × max(134, 170), so the open island always contains the strip; extend `hoveringADockedIslandNeverMovesItFromUnderThePointer` to the left and right edges. Fix any existing test that assumed 200 × 36 on a left/right edge.
- [x] **Step 4:** tests pass.
- [x] **Step 5:** commit `feat(core): lay a side-docked island out as a vertical strip`.

### Task 2: Platform on NowPlayingInfo (core)

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/MediaSite.swift`
- Modify: `NowPlaying/NowPlayingInfo.swift`, `NowPlaying/MediaRemotePayloadParser.swift`, `NowPlaying/AppleMusicPayloadParser.swift`
- Test: create `MediaSiteTests.swift`; extend both parser tests.

**Interfaces — produces:**

```swift
public enum MediaSite: String, Equatable, Sendable, CaseIterable {
    case youtube, kick, twitch
    public static func site(forPageURL url: String) -> MediaSite?
    public static func site(inPageTitle title: String) -> MediaSite?
}
// NowPlayingInfo: new stored properties, both defaulting to nil in `init`
public var sourceBundleIdentifier: String?
public var site: MediaSite?
```

- [x] **Step 1: Failing tests**

```swift
struct MediaSiteTests {
    @Test func hostDecidesTheSite() {
        #expect(MediaSite.site(forPageURL: "https://www.youtube.com/watch?v=abc") == .youtube)
        #expect(MediaSite.site(forPageURL: "https://music.youtube.com/watch?v=abc") == .youtube)
        #expect(MediaSite.site(forPageURL: "https://youtu.be/abc") == .youtube)
        #expect(MediaSite.site(forPageURL: "https://kick.com/lynxcerezlol") == .kick)
        #expect(MediaSite.site(forPageURL: "https://www.twitch.tv/riotgames") == .twitch)
    }

    @Test func lookalikeAndUnknownHostsAreNotSites() {
        #expect(MediaSite.site(forPageURL: "https://notyoutube.com/watch") == nil)
        #expect(MediaSite.site(forPageURL: "https://example.com/?next=youtube.com") == nil)
        #expect(MediaSite.site(forPageURL: "https://open.spotify.com/track/1") == nil)
        #expect(MediaSite.site(forPageURL: "missing value") == nil)
        #expect(MediaSite.site(forPageURL: "") == nil)
    }

    @Test func aPageTitleEndingInTheSiteNameNamesTheSite() {
        #expect(MediaSite.site(inPageTitle: "LynxCerezLoL Live Stream | Kick") == .kick)
        #expect(MediaSite.site(inPageTitle: "Some Video - YouTube") == .youtube)
        #expect(MediaSite.site(inPageTitle: "riotgames - Twitch") == .twitch)
        #expect(MediaSite.site(inPageTitle: "Watch on kick") == .kick)
    }

    @Test func aTitleThatOnlyMentionsASiteDoesNot() {
        #expect(MediaSite.site(inPageTitle: "GEN vs BLG | WORLDS 2026 | Finals") == nil)
        #expect(MediaSite.site(inPageTitle: "YouTube Rewind reaction") == nil)
        #expect(MediaSite.site(inPageTitle: "Sidekick") == nil)
        #expect(MediaSite.site(inPageTitle: "") == nil)
    }
}
```

Parser tests: a Safari payload gives `sourceBundleIdentifier == "com.apple.Safari"` (the parent, not the GPU helper) and `site == nil`; a payload with no identifier gives nil; the Apple Music parser gives `"com.apple.Music"`. Existing full-value comparisons gain `sourceBundleIdentifier:`.

- [x] **Step 2:** run, fails to compile.
- [x] **Step 3: Implement.** Host from `URLComponents(string:)?.host`, lowercased; a host matches a domain when it equals it or ends with `"." + domain`. Title: split on whitespace, take the last word stripped of punctuation, compare case-insensitively with `youtube`, `kick`, `twitch`.
- [x] **Step 4:** tests pass.
- [x] **Step 5:** commit `feat(core): carry the source app and site on NowPlayingInfo`.

### Task 3: Finding the playing tab (core)

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/NowPlaying/BrowserTabs.swift`
- Test: create `BrowserTabsTests.swift`

**Interfaces — produces:**

```swift
public struct BrowserTab: Equatable, Sendable { public var url: String; public var title: String }
public enum BrowserTabs {
    public static let fieldSeparator = "\u{1F}"   // between URL and title
    public static let recordSeparator = "\u{1E}"  // after every tab
    public static func parse(_ output: String) -> [BrowserTab]
    public static func playingTab(in tabs: [BrowserTab], trackTitle: String) -> BrowserTab?
}
```

- [x] **Step 1: Failing tests**

```swift
struct BrowserTabsTests {
    private func tab(_ url: String, _ title: String) -> BrowserTab { BrowserTab(url: url, title: title) }

    @Test func parsesRecordsAndSkipsBrokenOnes() {
        let output = "https://a.com\u{1F}A\u{1E}broken\u{1E}https://b.com\u{1F}B | C\u{1E}"
        #expect(BrowserTabs.parse(output) == [tab("https://a.com", "A"), tab("https://b.com", "B | C")])
        #expect(BrowserTabs.parse("") == [])
    }

    @Test func theTabWhoseTitleContainsTheTrackIsPlaying() {
        let tabs = [tab("https://news.example", "News"),
                    tab("https://www.youtube.com/watch?v=1", "(3) GEN vs BLG | Finals - YouTube")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "GEN vs BLG | Finals") == tabs[1])
    }

    @Test func aTrackNamedAfterThePageMatchesToo() {
        let tabs = [tab("https://kick.com/x", "x Live Stream")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "x Live Stream | Kick") == tabs[0])
    }

    @Test func amongMatchesAKnownSiteWins() {
        let tabs = [tab("https://search.example/?q=song", "Song - Search"),
                    tab("https://www.youtube.com/watch?v=2", "Song - YouTube")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "Song") == tabs[1])
    }

    @Test func withNoTitleMatchTheOnlyKnownSiteIsPlaying() {
        let tabs = [tab("https://news.example", "News"), tab("https://www.twitch.tv/riot", "riot - Twitch")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "Worlds day 3") == tabs[1])
    }

    @Test func twoKnownSitesAndNoTitleMatchIsUndecided() {
        let tabs = [tab("https://www.youtube.com/", "YouTube"), tab("https://www.twitch.tv/riot", "riot - Twitch")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "Worlds day 3") == nil)
    }

    @Test func shortOrEmptyTitlesNeverMatch() {
        let tabs = [tab("https://a.example", "A"), tab("https://b.example", "")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "A long track name") == nil)
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "") == nil)
    }
}
```

- [x] **Step 2:** run, fails to compile.
- [x] **Step 3: Implement.** Match is case-insensitive containment either way; the contained string must be at least 4 characters.
- [x] **Step 4:** tests pass.
- [x] **Step 5:** commit `feat(core): find the browser tab that is playing`.

### Task 4: The strip (app views)

**Files:**
- Create: `Symbiodock/Island/SideCollapsedContent.swift`, `Symbiodock/Island/PlatformIcon.swift`
- Create: `Symbiodock/Resources/PlatformIcons/youtube.svg`, `kick.svg`, `twitch.svg` (Simple Icons 13 paths; brand fills `#FF0000`, `#53FC18`, `#9146FF`; white behind YouTube's play triangle and Twitch's bubble)
- Modify: `Symbiodock/Island/IslandView.swift` (side-docked collapsed → `SideCollapsedContent`), `Symbiodock/Island/DragSession.swift` (`islandPath` capsule radius: `min(min(frame.width, frame.height) / 2, 18)`), `Symbiodock/Resources/ThirdPartyNotices.txt`

**Interfaces — consumes:** `IslandLayout.isSideDocked`, `NowPlayingInfo.site`, `.sourceBundleIdentifier`. **Produces:** `PlatformIcon(info: NowPlayingInfo, size: CGFloat)`, `SideCollapsedContent(info: NowPlayingInfo?)`.

- [x] **Step 1:** `PlatformIcon`: site → cached `NSImage` from `Bundle.main.url(forResource: site.rawValue, withExtension: "svg")`; else bundle identifier → `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` → `icon(forFile:)`, cached; else the `music.note` glyph on the same tile `ArtworkView` uses.
- [x] **Step 2:** `SideCollapsedContent`: `VStack` of icon (20 pt), rotated title, `LevelBars`. The title is laid out with the strip's free height as its width, then turned:

```swift
GeometryReader { proxy in
    Text(title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white)
        .lineLimit(1)
        .frame(width: proxy.size.height, height: proxy.size.width, alignment: .leading)
        .rotationEffect(.degrees(90))
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
}
```

- [x] **Step 3:** wire into `IslandView.content(atNotch:)`; fix the capsule radius in `DragSession.islandPath`.
- [x] **Step 4:** `xcodegen generate && xcodebuild …` builds; the SVGs are in `Contents/Resources`.
- [x] **Step 5:** run the app docked on a side edge and look at it (screenshot).
- [x] **Step 6:** commit `feat: show a side-docked island as a vertical strip`.

### Task 5: Site detection (app)

**Files:**
- Create: `Symbiodock/NowPlaying/SiteResolver.swift`, `Symbiodock/NowPlaying/BrowserTabScript.swift`
- Modify: `Symbiodock/NowPlaying/NowPlayingCoordinator.swift` (route `onUpdate` through the resolver), `Symbiodock/Info.plist` and `project.yml` (`NSAppleEventsUsageDescription`: "Symbiodock reads the current track from Music, controls playback, and asks your browser which site is playing.")

**Interfaces — consumes:** `BrowserTabs`, `MediaSite`, `AppleScriptRunner.run`. **Produces:**

```swift
@MainActor final class SiteResolver {
    init(onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void)
    func publish(_ info: NowPlayingInfo?)
}
@MainActor enum BrowserTabScript {
    static func supports(_ bundleIdentifier: String) -> Bool   // Safari, Google Chrome
    static func tabs(of bundleIdentifier: String) async -> [BrowserTab]?  // nil: denied, not running, failed
}
```

- [x] **Step 1:** `BrowserTabScript`. Permission off the main thread:

```swift
private nonisolated static func automationStatus(_ bundleIdentifier: String) async -> OSStatus {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            continuation.resume(returning: AEDeterminePermissionToAutomateTarget(
                target.aeDesc, typeWildCard, typeWildCard, true))
        }
    }
}
```

The script, with `<title>` = `name` for Safari and `title` for Chrome:

```applescript
tell application id "<bundle id>"
    with timeout of 2 seconds
        set out to ""
        repeat with w in windows
            try
                set us to URL of tabs of w
                set ns to <title> of tabs of w
                repeat with i from 1 to count of us
                    try
                        set out to out & ((item i of us) as text) & (ASCII character 31) ¬
                            & ((item i of ns) as text) & (ASCII character 30)
                    end try
                end repeat
            end try
        end repeat
        return out
    end timeout
end tell
```

Run it only when the browser is running (`NSRunningApplication`), so it is never launched.

- [x] **Step 2:** `SiteResolver.publish`: non-browser → pass through. Browser → set `site` from the cache when `(bundle, title)` matches the cached key, otherwise from `MediaSite.site(inPageTitle:)`; publish; if the key is not cached and no lookup is running, start one. When a lookup ends: cache `(key, site)`, republish the latest info if its key matches, and start another lookup if the latest key differs.
- [x] **Step 3:** wire into `NowPlayingCoordinator`; update the usage description in both files.
- [x] **Step 4:** build; run with a browser playing; the owner allows the prompt; the logo appears.
- [x] **Step 5:** commit `feat: show the playing site's logo for browser playback`.

### Task 6: Records

- [x] Add the decisions (side docking, platform icon, browser Automation) to the decision table and `Durum` in `CLAUDE.md`; note the unverified parts (prompt, Chrome, Kick/Twitch titles).
- [x] Append the hand checklist below to this plan.
- [x] Commit `docs: record side docking and the platform icon`.

## Hand checklist (owner)

1. Dock the island on the left edge, then the right: a vertical strip, flush with the edge, square corners on the edge.
2. Hover: it opens sideways into the screen and closes back into the strip.
3. Drag it off a side edge: it becomes the horizontal capsule; release near a side edge: it springs back into a strip.
4. Corners, top and bottom edges: still horizontal.
5. Play YouTube in Safari: allow the Automation prompt once; the strip shows the YouTube logo.
6. The same in Chrome; and Kick and Twitch.
7. Apple Music and Spotify: the app's own icon.
8. Deny the prompt (or `tccutil reset AppleEvents com.yigtwxx.Symbiodock`, then deny): the browser's icon, no repeated prompts.
