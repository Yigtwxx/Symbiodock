# Side docking and platform icon

Date: 2026-11-14
Status: approved by the owner on 2026-11-14.
Extends: `2026-11-14-symbiodock-v1-design.md` (sections 5.4, 5.7, 5.8).

## 1. Goal

An island docked on the left or right screen edge lies along that edge instead of
sticking out from it:

1. Collapsed, it is a vertical strip: the platform's icon on top, the track title
   rotated a quarter turn in the middle, the level bars at the bottom.
2. Hovered, it opens sideways, from the edge into the screen, as the same expanded
   island every other anchor shows.
3. The platform icon says where the sound comes from: the Music or Spotify app
   icon, or the logo of the site playing in a browser (YouTube, Kick, Twitch).

## 2. Scope

In scope:

- Vertical collapsed layout for `.edge(.left, _)` and `.edge(.right, _)`.
- Platform detection and the icon, shown in the vertical strip only.

Out of scope:

- Corners and the top and bottom edges: they keep the horizontal island.
- The platform icon in the expanded island or the horizontal collapsed island.
- Browsers other than Safari and Google Chrome.
- A menu item for denied browser access; a denied request falls back silently.

## 3. Layout (core)

- `IslandLayout.sideCollapsedSize` is 36 × 170 pt.
- `IslandLayout.isSideDocked(_:)` is true for an edge anchor on the left or right.
- `IslandLayout.frame(anchor:…)` places `sideCollapsedSize` for a side-docked,
  collapsed island. Everything else is unchanged: the strip is flush with the
  visible frame, centred on the anchor's fraction, clamped to the frame, and moved
  below the notch if it would meet it. The expanded island keeps the same centre,
  so it grows out of the strip.
- Opened from a strip the island is 480 × 170: as tall as the strip. Were it shorter,
  hovering the strip's end would leave the pointer outside the open island, which
  would then close and open forever.
- `cornerRadii` needs no change: it already squares the corners on the docked edge.

## 4. Dragging

`DragSession` already springs the body to whatever frame it is given, so the
strip needs no new code path:

- Grabbed from a side dock, the body starts as the strip, and becomes the
  horizontal capsule (`floatingCollapsedSize`) when it tears off.
- Released towards a side edge, it springs into the strip while it glides there.
- The carried body's capsule radius is half its shorter side (at most 18 pt), so a
  strip that has not torn off yet is still a capsule.

## 5. Platform detection

`NowPlayingInfo` gains two fields:

- `sourceBundleIdentifier: String?` — the app the sound comes from. Set by both
  payload parsers (`com.apple.Music` for the Apple Music provider).
- `site: MediaSite?` — the web site, when the app is a browser and the site is
  known. `MediaSite` is `youtube`, `kick` or `twitch`.

Core, pure and tested:

- `MediaSite.site(forPageURL:)` — by host: `youtube.com`, `youtu.be` and their
  subdomains; `kick.com`; `twitch.tv`.
- `MediaSite.site(inPageTitle:)` — the title's last word names the site (a browser
  reports the page title as the track when the page sets no metadata: "… | Kick").
- `BrowserTabs.parse(_:)` — the tab script's reply into `(url, title)` pairs.
- `BrowserTabs.playingTab(in:trackTitle:)` — the tab whose title contains the track
  title (or the reverse), preferring one on a known site; with no such tab, the
  only tab on a known site if there is exactly one; otherwise nil.

App, `SiteResolver` (main actor), between `NowPlayingService` and `IslandState`:

1. An update from an app that is not a supported browser passes through with
   `site == nil`.
2. For a browser, the update is published at once with the site read from the
   title, or the cached site if the bundle identifier and title are unchanged.
3. When bundle identifier or title changed, a lookup starts (one at a time):
   - Off the main thread, `AEDeterminePermissionToAutomateTarget` asks for
     Automation access, prompting the first time. The wait for the user's answer
     never blocks the main thread.
   - If granted and the browser is running, one AppleScript (2 s timeout) reads
     the URL and title of every tab, two Apple Events per window.
   - The result is cached. If the current track is still the one looked up, the
     update is published again with the site.
4. Denied access, a script failure or an unknown site leave the title's answer.

Privacy: tab URLs and titles are held only for the comparison. They are never
logged or stored.

`NSAppleEventsUsageDescription` is reworded to cover browsers.

## 6. Views

- `PlatformIcon(info:size:)`: the site's logo if `site` is set; otherwise the icon
  of the app with `sourceBundleIdentifier`; otherwise the music glyph.
  - Site logos are SVG resources from Simple Icons (CC0), filled with the brand
    colour, loaded once with `NSImage` and cached. No network access.
  - App icons come from `NSWorkspace` and are cached by bundle identifier.
- `SideCollapsedContent(info:)`: the strip. Icon (20 pt) on top, the title rotated
  90° clockwise so it reads from the top down and truncates at the bars, the level
  bars upright at the bottom (dimmed while paused). With nothing playing: the music
  glyph and "Nothing playing".
- `IslandView` shows `SideCollapsedContent` for a collapsed, side-docked island.

## 7. Testing

- Core tests: side frames (both edges, fraction, clamping, expanded keeps the
  centre, corners and top/bottom unchanged), `MediaSite`, `BrowserTabs`, both
  parsers setting `sourceBundleIdentifier`.
- App: build, then look at the running app docked on a side edge.
- By hand (owner): the Automation prompt for Safari and Chrome, the logo for
  YouTube, Kick and Twitch, dragging off and back onto a side edge.
