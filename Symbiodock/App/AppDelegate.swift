import AppKit
import SymbiodockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private var islandMenu: IslandMenu?
    private var overlayController: OverlayController?
    private var nowPlaying: NowPlayingCoordinator?
    private var agents: AgentSessionCoordinator?
    private var system: SystemCoordinator?
    private let previews = FilePreviews()
    private var shelf: ShelfCoordinator?
    private var terminationSignalSource: DispatchSourceSignal?
    private var wingsExpiry: Task<Void, Never>?
    /// The paused sources the running `wingsExpiry` waits for.
    private var wingsExpiryOrigins: Set<NowPlayingOrigin> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DebugRender.runIfRequested()
        if ConvertHook.runIfRequested() || FlowHook.runIfRequested() || SystemHook.runIfRequested() { return }
        #endif
        installTerminationHandler()

        let islandMenu = IslandMenu()
        self.islandMenu = islandMenu

        state.setTabOrder(TabOrderStore.load())

        let overlayController = OverlayController(
            state: state, contextMenu: islandMenu.menu,
            onCommand: { [weak self] command, origin in
                self?.nowPlaying?.send(command, to: origin)
            },
            onVolume: { [weak self] request in self?.handleVolume(request) },
            onOpenSession: { session in
                if let pid = session.hostAppPID { HostApp.bringForward(pid: pid) }
            },
            previews: previews,
            onFile: { [weak self] request in self?.shelf?.handle(request) })
        wireFileDrags(overlayController)
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

        startShelf(islandMenu: islandMenu)

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
        if let demo = DemoSystem.requested {
            DemoSystem.apply(demo, to: state)
        } else {
            startSystem()
        }
        #else
        startSystem()
        #endif

        #if DEBUG
        if DemoMedia.requested {
            DemoMedia.apply(to: state)
            if DemoMedia.cyclesTracks { DemoMedia.cycleTracks(on: state) }
            overlayController.refreshPointer()
            return
        }
        #endif

        let nowPlaying = NowPlayingCoordinator(
            onUpdate: { [weak self] info in
                self?.state.setNowPlaying(info)
                self?.mediaDidChange()
            },
            onCompanionUpdate: { [weak self] info in
                self?.state.setCompanionPlaying(info)
                self?.mediaDidChange()
            },
            onOthersUpdate: { [weak self] clients in
                self?.state.setOtherPlaying(clients)
                self?.mediaDidChange()
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
        system?.stop()
        shelf?.stop()
    }

    /// Brings the shelf back, or lays out a demo one; the menu's `Clear Files` empties it. The
    /// tools its conversions run are stopped with it, on quit.
    private func startShelf(islandMenu: IslandMenu) {
        let converter = FileConverter(runner: ToolRunner(helpers: HelperProcesses()))
        let shelf = ShelfCoordinator(state: state, previews: previews, converter: converter)
        self.shelf = shelf
        islandMenu.hasFiles = { [weak self] in !(self?.state.shelf.isEmpty ?? true) }
        islandMenu.onClearFiles = { [weak shelf] in shelf?.clear() }
        #if DEBUG
        if let demo = DemoFiles.requested {
            shelf.isDemo = true
            if let request = DemoFiles.apply(demo, to: state, previews: previews) {
                shelf.handle(request)
            }
            return
        }
        #endif
        shelf.start()
        #if DEBUG
        if let file = DemoFiles.fileToAdd { shelf.add([file]) }
        #endif
    }

    /// Dropped files go on the shelf; files dragged within the island change stacks; files
    /// taken by another app leave it; a click on a stack picks.
    private func wireFileDrags(_ overlayController: OverlayController) {
        overlayController.onDropFiles = { [weak self] urls, stack in self?.shelf?.add(urls, onto: stack) }
        overlayController.onMoveFiles = { [weak self] ids, stack in self?.shelf?.move(ids, onto: stack) }
        overlayController.onPickFile = { [weak self] stack, hit, command in
            self?.shelf?.pick(stack, hit, command: command)
        }
        overlayController.onFilesDraggedOut = { [weak self] ids in self?.shelf?.removeAfterDragOut(ids) }
        overlayController.fileURL = { [weak self] id in
            // A converting file is about to change; it stays until the reveal is over.
            guard let self, self.state.conversions[id] == nil else { return nil }
            return self.shelfItem(id)?.url
        }
        overlayController.dragImage = { [weak self] id in
            // What the card shows: its picture, or its kind's symbol on its glass.
            guard let self, let item = self.shelfItem(id) else { return nil }
            return self.previews.image(for: item) ?? KindSymbolCard.image(for: item.kind)
        }
    }

    private func shelfItem(_ id: UUID) -> ShelfItem? {
        state.shelf.items.first { $0.id == id }
    }

    /// Starts measuring this Mac whenever the open island shows the System tab.
    private func startSystem() {
        let system = SystemCoordinator(
            isWatching: { [weak self] in
                self.map { $0.state.phase == .expanded && $0.state.selectedTab == .system } ?? false
            },
            onUpdate: { [weak self] snapshot, history in
                self?.state.setSystem(snapshot, history: history)
            })
        system.start()
        self.system = system
    }

    /// Starts looking for agent sessions.
    private func startAgents() {
        let agents = AgentSessionCoordinator(
            providers: AgentProviders.all(),
            wakeFolders: AgentProviders.wakeFolders(),
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

    /// The players are asked on the main actor: AppleScript is not thread-safe.
    private func handleVolume(_ request: VolumeRequest) {
        #if DEBUG
        // The demo's players are not running; keep the level the demo set.
        if DemoMedia.requested, case .read = request { return }
        #endif
        switch request {
        case .read(let target):
            state.setVolume(PlayerVolumeScript.read(target), for: target)
        case .set(let target, let fraction):
            state.setVolume(fraction, for: target)
            PlayerVolumeScript.set(target, to: fraction)
        }
    }

    private func mediaDidChange() {
        scheduleWingsExpiry()
        // The collapsed hit rect depends on whether the wings are shown.
        overlayController?.refreshPointer()
        // Which listed browser is asked for its site depends on the slots.
        nowPlaying?.slotsChanged(state.mediaSlots)
    }

    /// Hides the collapsed wings, and a second source, a while after they pause, unless
    /// they resume first.
    private func scheduleWingsExpiry() {
        let paused = Set(state.mediaSlots.filter { !$0.info.isPlaying }.map(\.origin))
        // A playing source reports often; that must not restart the wait of a paused one.
        guard paused != wingsExpiryOrigins else { return }
        wingsExpiryOrigins = paused
        wingsExpiry?.cancel()
        wingsExpiry = nil
        guard !paused.isEmpty else { return }
        wingsExpiry = Task { [weak self] in
            try? await Task.sleep(for: WingsTiming.pausedGrace)
            guard !Task.isCancelled, let self else { return }
            self.wingsExpiryOrigins = []
            self.state.pausedGraceElapsed()
            self.overlayController?.refreshPointer()
            // A retired browser is no longer asked for its site.
            self.nowPlaying?.slotsChanged(self.state.mediaSlots)
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
