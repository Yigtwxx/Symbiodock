import AppKit
import SymbiodockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private var islandMenu: IslandMenu?
    private var overlayController: OverlayController?
    private var nowPlaying: NowPlayingCoordinator?
    private var terminationSignalSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationHandler()

        let islandMenu = IslandMenu()
        self.islandMenu = islandMenu

        let overlayController = OverlayController(
            state: state, contextMenu: islandMenu.menu
        ) { [weak self] command in
            self?.nowPlaying?.send(command)
        }
        overlayController.start()
        self.overlayController = overlayController

        let nowPlaying = NowPlayingCoordinator { [weak self] info in
            self?.state.setNowPlaying(info)
            // The collapsed hit rect depends on whether there is a track.
            self?.overlayController?.refreshPointer()
        }
        nowPlaying.start()
        self.nowPlaying = nowPlaying
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Otherwise the perl helper would outlive the app until its next write.
        nowPlaying?.stop()
    }

    /// A plain SIGTERM (`pkill`, `kill`) skips `applicationWillTerminate`, which would leave the
    /// perl helper running. Route it through the normal quit path instead.
    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignalSource = source
    }
}
