import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var overlayController: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController()

        let overlayController = OverlayController()
        overlayController.start()
        self.overlayController = overlayController
    }
}
