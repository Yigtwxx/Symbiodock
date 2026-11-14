import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandMenu: IslandMenu?
    private var overlayController: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let islandMenu = IslandMenu()
        self.islandMenu = islandMenu

        let overlayController = OverlayController(contextMenu: islandMenu.menu)
        overlayController.start()
        self.overlayController = overlayController
    }
}
