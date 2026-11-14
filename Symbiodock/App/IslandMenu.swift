import AppKit

/// The island's context menu, shown on a secondary click.
///
/// Symbiodock is an agent app without a Dock icon or a menu bar item,
/// so this menu is the only way to quit.
@MainActor
final class IslandMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let musicAccessItem: NSMenuItem
    private let musicAccessSeparator = NSMenuItem.separator()
    private let launchAtLoginItem: NSMenuItem

    override init() {
        musicAccessItem = NSMenuItem(
            title: "Music access needed", action: #selector(openAutomationSettings), keyEquivalent: "")
        launchAtLoginItem = NSMenuItem(
            title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        super.init()

        menu.delegate = self

        musicAccessItem.target = self
        menu.addItem(musicAccessItem)
        menu.addItem(musicAccessSeparator)

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

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

    /// The checkmark reflects the system's real status each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
