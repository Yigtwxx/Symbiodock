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
