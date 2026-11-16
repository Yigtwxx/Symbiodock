import Foundation
import SymbiodockCore

/// Builds the providers and keeps the Now Playing service running.
@MainActor
final class NowPlayingCoordinator {
    private let service: NowPlayingService
    private let helpers = HelperProcesses()
    private var task: Task<Void, Never>?
    /// Apple Music asked directly while the system-wide source speaks for something else;
    /// nil when Apple Music is itself the only source.
    private let companion: AppleMusicProvider?
    private let onCompanionUpdate: @MainActor (NowPlayingInfo?) -> Void
    private var companionTask: Task<Void, Never>?
    // One consumer runs the commands one after another, in the order they were issued.
    private let commands: AsyncStream<(PlaybackCommand, NowPlayingOrigin)>
    private let commandSink: AsyncStream<(PlaybackCommand, NowPlayingOrigin)>.Continuation
    private var commandTask: Task<Void, Never>?

    init(
        onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void,
        onCompanionUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void,
        onMusicAccessChange: @escaping @MainActor @Sendable (_ denied: Bool) -> Void
    ) {
        let appleMusic = AppleMusicProvider(onConsentChange: onMusicAccessChange)
        var providers: [any NowPlayingProvider] = []
        // SYMBIODOCK_PROVIDER=applemusic skips the system-wide source, to verify the fallback.
        let appleMusicOnly =
            ProcessInfo.processInfo.environment["SYMBIODOCK_PROVIDER"] == "applemusic"
        if !appleMusicOnly, let paths = MediaRemoteProvider.Paths.inMainBundle() {
            providers.append(MediaRemoteProvider(paths: paths, helpers: helpers))
        }
        // The system names one source only; Music is asked as well, to show both at once.
        companion = providers.isEmpty ? nil : appleMusic
        self.onCompanionUpdate = onCompanionUpdate
        providers.append(appleMusic)
        // The service names the app; the resolver adds the site when the app is a browser.
        let siteResolver = SiteResolver(onUpdate: onUpdate)
        service = NowPlayingService(providers: providers) { siteResolver.publish($0) }
        (commands, commandSink) = AsyncStream.makeStream(of: (PlaybackCommand, NowPlayingOrigin).self)
    }

    func start() {
        guard task == nil else { return }
        task = Task { await service.run() }
        let service = service
        let commands = commands
        let companion = companion
        commandTask = Task {
            for await (command, origin) in commands {
                switch origin {
                case .system: await service.send(command)
                case .companion: await companion?.send(command)
                // No client slot is fed yet, so there is nothing to route.
                case .client: break
                }
            }
        }
        if let companion {
            let onCompanionUpdate = onCompanionUpdate
            companionTask = Task {
                guard await companion.isAvailable() else { return }
                for await info in companion.updates { onCompanionUpdate(info) }
            }
        }
    }

    /// Cancelling ends the provider's stream, which terminates the helper process; that
    /// happens asynchronously, so the helpers are also stopped before this returns.
    func stop() {
        task?.cancel()
        task = nil
        commandTask?.cancel()
        commandTask = nil
        companionTask?.cancel()
        companionTask = nil
        commandSink.finish()
        helpers.terminateAll()
    }

    func send(_ command: PlaybackCommand, to origin: NowPlayingOrigin) {
        commandSink.yield((command, origin))
    }
}
