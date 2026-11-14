import AppKit

/// The island's context menu, shown on a secondary click.
///
/// Symbiodock is an agent app without a Dock icon or a menu bar item,
/// so this menu is the only way to quit.
@MainActor
final class IslandMenu {
    let menu = NSMenu()

    init() {
        let quit = NSMenuItem(
            title: "Quit Symbiodock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "")
        quit.target = NSApplication.shared
        menu.addItem(quit)
    }
}
