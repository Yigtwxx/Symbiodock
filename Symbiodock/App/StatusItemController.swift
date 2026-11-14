import AppKit

/// The menu bar item. An agent app has no Dock icon, so this is the only way to quit.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "drop.fill",
            accessibilityDescription: "Symbiodock")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit Symbiodock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
