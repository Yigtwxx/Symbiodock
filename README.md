# Symbiodock

A living notch for your MacBook. Symbiodock turns the notch into an island that
expands on hover, shows what you are playing, and can be pulled away from the
notch with a symbiote-like stretch effect to dock on any screen edge or corner.

## Status

Early development; not released. All features planned for the first version are
implemented, but several have not been tried by hand yet:

| Feature | State |
|---|---|
| Notch island, expands on hover, clicks pass through | Works |
| Now Playing: artwork, title, artist, progress, previous / play-pause / next | Implemented, awaiting a manual check |
| Collapsed wings beside the notch (artwork and level bars) | Implemented, awaiting a manual check |
| Drag the island off the notch with a stretching, tearing "symbiote" effect | Implemented, awaiting a manual check |
| Snap to any screen edge or corner, remembered across launches | Implemented, awaiting a manual check |
| Launch at login | Implemented, awaiting a manual check |

## Using it

Symbiodock has no Dock icon and no menu bar item.

- Move the pointer onto the notch to open the island.
- Press on the island and pull to drag it away. Past about 120 pt it tears off;
  let go near an edge or a corner and it settles there. Let go near the notch and
  it goes back.
- Right-click (or Control-click) the island for its menu: Return to notch,
  Launch at login, Quit.

## Building from source

Requirements: macOS 14 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone https://github.com/Yigtwxx/Symbiodock.git
cd Symbiodock
xcodegen generate
xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Symbiodock.app
```

The build is ad-hoc signed and meant to run on the machine that built it.

Run the unit tests of the core logic with:

```bash
swift test --package-path Packages/SymbiodockCore
```

## How it reads what is playing

macOS has no public API for system-wide Now Playing. Symbiodock uses two sources
behind one interface:

- The bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
  helper, which covers every app, including browsers. It runs inside `/usr/bin/perl`.
- Apple Music through Apple Events, as a fallback. macOS asks for permission the
  first time this is used.

Nothing about what you play leaves your Mac, and none of it is written to logs.

## Tech

- Swift 6, SwiftUI for views, AppKit for the window
- macOS 14 or later
- Pure logic in `Packages/SymbiodockCore`, unit-tested without launching the app

## Design

The v1 design is described in
[docs/superpowers/specs/2026-11-14-symbiodock-v1-design.md](docs/superpowers/specs/2026-11-14-symbiodock-v1-design.md).

## Third-party code

Symbiodock bundles [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
by Jonas van den Berg and contributors, under the BSD 3-Clause License. Its sources and
license are in `Vendor/mediaremote-adapter`.

## License

Copyright (C) 2026 Yigtwxx

Symbiodock is free software, licensed under the
[GNU General Public License v3.0](LICENSE).
