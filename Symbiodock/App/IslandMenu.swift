import AppKit
import SymbiodockCore

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
    private let returnToNotchItem: NSMenuItem
    private let firstTabItem = NSMenuItem(title: "First tab", action: nil, keyEquivalent: "")
    private var tabItems: [(tab: IslandTab, item: NSMenuItem)] = []

    /// Set by the app: the tab that is first now.
    var firstTab: () -> IslandTab = { TabOrder.default[0] }
    /// Set by the app: the user chose a tab to be first.
    var onChooseFirstTab: ((IslandTab) -> Void)?

    /// Set by the app: puts the island back on the notch.
    var onReturnToNotch: (() -> Void)?
    /// Set by the app: whether the island is somewhere other than the notch.
    var canReturnToNotch: () -> Bool = { false }

    override init() {
        musicAccessItem = NSMenuItem(
            title: "Music access needed", action: #selector(openAutomationSettings), keyEquivalent: "")
        launchAtLoginItem = NSMenuItem(
            title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        returnToNotchItem = NSMenuItem(
            title: "Return to notch", action: #selector(returnToNotch), keyEquivalent: "")
        super.init()

        menu.delegate = self
        // "Return to notch" is greyed out by hand while the island is already there.
        menu.autoenablesItems = false

        musicAccessItem.target = self
        menu.addItem(musicAccessItem)
        menu.addItem(musicAccessSeparator)

        returnToNotchItem.target = self
        menu.addItem(returnToNotchItem)

        let tabMenu = NSMenu()
        for tab in TabOrder.default {
            let item = NSMenuItem(
                title: tab.title, action: #selector(chooseFirstTab(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tab.rawValue
            tabMenu.addItem(item)
            tabItems.append((tab, item))
        }
        firstTabItem.submenu = tabMenu
        menu.addItem(firstTabItem)

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
        // A dash means it is registered but waiting for the user's approval in System Settings.
        launchAtLoginItem.state = LoginItem.isEnabled ? .on : (LoginItem.needsApproval ? .mixed : .off)
        returnToNotchItem.isEnabled = canReturnToNotch()
        let first = firstTab()
        for (tab, item) in tabItems { item.state = tab == first ? .on : .off }
    }

    @objc private func returnToNotch() {
        onReturnToNotch?()
    }

    @objc private func chooseFirstTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = IslandTab(rawValue: raw)
        else { return }
        onChooseFirstTab?(tab)
    }

    @objc private func toggleLaunchAtLogin() {
        if LoginItem.needsApproval {
            // Registering again would do nothing; the switch is in System Settings.
            LoginItem.openSystemSettings()
            return
        }
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
