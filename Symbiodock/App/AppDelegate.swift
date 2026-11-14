import AppKit
import SymbiodockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private var islandMenu: IslandMenu?
    private var overlayController: OverlayController?
    private var nowPlaying: NowPlayingCoordinator?
    private var agents: AgentSessionCoordinator?
    private var terminationSignalSource: DispatchSourceSignal?
    private var wingsExpiry: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugRender.runIfRequested()
        #endif
        installTerminationHandler()

        let islandMenu = IslandMenu()
        self.islandMenu = islandMenu

        state.setTabOrder(TabOrderStore.load())

        let overlayController = OverlayController(
            state: state, contextMenu: islandMenu.menu,
            onCommand: { [weak self] command in
                self?.nowPlaying?.send(command)
            },
            onOpenSession: { session in
                if let pid = session.hostAppPID { HostApp.bringForward(pid: pid) }
            })
        overlayController.start()
        self.overlayController = overlayController
        islandMenu.onReturnToNotch = { [weak overlayController] in overlayController?.returnToNotch() }
        islandMenu.canReturnToNotch = { [weak self] in self.map { $0.state.anchor != .notch } ?? false }
        islandMenu.firstTab = { [weak self] in self?.state.tabOrder.first ?? TabOrder.default[0] }
        islandMenu.onChooseFirstTab = { [weak self] tab in
            guard let self else { return }
            let order = TabOrder.moving(tab, toFrontOf: self.state.tabOrder)
            self.state.setTabOrder(order)
            TabOrderStore.save(order)
            // The collapsed face, and with it the hit rect, may have changed.
            self.overlayController?.refreshPointer()
        }

        #if DEBUG
        if let demo = DemoAgents.requested {
            DemoAgents.apply(demo, to: state)
            overlayController.refreshPointer()
        } else {
            startAgents()
        }
        #else
        startAgents()
        #endif

        #if DEBUG
        if DemoMedia.requested {
            DemoMedia.apply(to: state)
            overlayController.refreshPointer()
            return
        }
        #endif

        let nowPlaying = NowPlayingCoordinator(
            onUpdate: { [weak self] info in
                self?.state.setNowPlaying(info)
                self?.scheduleWingsExpiry(for: info)
                // The collapsed hit rect depends on whether the wings are shown.
                self?.overlayController?.refreshPointer()
            },
            onMusicAccessChange: { [weak self] denied in
                self?.islandMenu?.setMusicAccessNeeded(denied)
            })
        nowPlaying.start()
        self.nowPlaying = nowPlaying
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Otherwise the perl helper would outlive the app until its next write.
        nowPlaying?.stop()
        agents?.stop()
    }

    /// Starts looking for agent sessions.
    private func startAgents() {
        let agents = AgentSessionCoordinator(
            providers: AgentProviders.all(),
            isWatching: { [weak self] in
                self.map { $0.state.phase == .expanded && $0.state.selectedTab == .agents } ?? false
            },
            onUpdate: { [weak self] sessions in
                guard let self else { return }
                let hadWings = self.state.showsWings
                self.state.setAgentSessions(sessions)
                // The collapsed hit rect depends on whether the wings are shown.
                if self.state.showsWings != hadWings { self.overlayController?.refreshPointer() }
            })
        agents.start()
        self.agents = agents
    }

    /// Hides the collapsed wings a while after playback pauses, unless it resumes first.
    private func scheduleWingsExpiry(for info: NowPlayingInfo?) {
        wingsExpiry?.cancel()
        wingsExpiry = nil
        guard let info, !info.isPlaying else { return }
        wingsExpiry = Task { [weak self] in
            try? await Task.sleep(for: WingsTiming.pausedGrace)
            guard !Task.isCancelled, let self else { return }
            self.state.pausedGraceElapsed()
            self.overlayController?.refreshPointer()
        }
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
