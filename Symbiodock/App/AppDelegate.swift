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
