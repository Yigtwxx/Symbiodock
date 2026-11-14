# Milestone 5: Launch at Login — Implementation Plan

**Goal:** The island menu has a "Launch at login" entry with a checkmark that registers and unregisters Symbiodock as a login item.

**Architecture:** One file, `Symbiodock/App/LoginItem.swift`, wraps `SMAppService.mainApp`. `IslandMenu` owns the menu entry and reads the real service status every time the menu opens (`NSMenuDelegate.menuNeedsUpdate`), so the checkmark never drifts from what the system has. No state of our own is stored.

**Spec:** `docs/superpowers/specs/2026-11-14-symbiodock-v1-design.md`, sections 5.9 and 6.

## Global Constraints

- Minimum macOS 14.0, Swift 6. `SMAppService` needs no helper bundle for the main app.
- The entry lives in the island's context menu (there is no menu bar item), between "Music access needed" and "Quit Symbiodock".
- Registration failure: the entry stays unchecked and the error is logged with `os.Logger` (spec section 6). Nothing is shown to the user.
- User-facing text in English as a plain literal: `Launch at login`.

## Task 1: Login item wrapper and menu entry

**Files:**
- Create: `Symbiodock/App/LoginItem.swift`
- Modify: `Symbiodock/App/IslandMenu.swift`
- Modify: `CLAUDE.md` (sections "Durum", "Yol haritası")

**Interfaces:**
- `@MainActor enum LoginItem` with `static var isEnabled: Bool { get }` and `static func setEnabled(_ enabled: Bool)`.
- `IslandMenu` conforms to `NSMenuDelegate`; `menuNeedsUpdate(_:)` sets the entry's `state`.

Steps:

- [ ] Write `LoginItem.swift`: `isEnabled` is `SMAppService.mainApp.status == .enabled`; `setEnabled` calls `register()` or `unregister()` in a `do`/`catch` and logs failures (category `LoginItem`).
- [ ] In `IslandMenu`, add the "Launch at login" item above "Quit Symbiodock" with a separator between them, set `menu.delegate = self`, toggle through `LoginItem.setEnabled(!LoginItem.isEnabled)`, and refresh the checkmark in `menuNeedsUpdate`.
- [ ] Build: `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | grep -E "warning:|error:|BUILD" | sort -u` → `** BUILD SUCCEEDED **`.
- [ ] Tick `Faz 6` in `CLAUDE.md` and update `Durum`. Commit `feat(app): add launch at login to the island menu`, push.

## Manual checklist for the owner

1. Right-click the island. "Launch at login" is there, unchecked.
2. Choose it. macOS may show a "login item added" notification. Open the menu again: it is checked, and System Settings → General → Login Items lists Symbiodock.
3. Quit and relaunch Symbiodock. The entry is still checked.
4. Choose it again. It is unchecked and Symbiodock is gone from Login Items.
5. Check it again, then switch Symbiodock off in System Settings → General → Login Items. The menu entry now shows a dash, and choosing it opens that settings pane.

Note: a login item points at the app's current location. While the app runs from `build/`, a rebuild or `rm -rf build` breaks the item; this is expected until the app is installed in `/Applications`.
