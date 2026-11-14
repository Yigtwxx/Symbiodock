import Foundation
import SymbiodockCore

/// Builds the providers and keeps the Now Playing service running.
@MainActor
final class NowPlayingCoordinator {
    private let service: NowPlayingService
    private let helpers = HelperProcesses()
    private var task: Task<Void, Never>?
    // One consumer runs the commands one after another, in the order they were issued.
    private let commands: AsyncStream<PlaybackCommand>
    private let commandSink: AsyncStream<PlaybackCommand>.Continuation
    private var commandTask: Task<Void, Never>?

    init(
        onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void,
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
        providers.append(appleMusic)
        service = NowPlayingService(providers: providers, onUpdate: onUpdate)
        (commands, commandSink) = AsyncStream.makeStream(of: PlaybackCommand.self)
    }

    func start() {
        guard task == nil else { return }
        task = Task { await service.run() }
        let service = service
        let commands = commands
        commandTask = Task {
            for await command in commands { await service.send(command) }
        }
    }

    /// Cancelling ends the provider's stream, which terminates the helper process; that
    /// happens asynchronously, so the helpers are also stopped before this returns.
    func stop() {
        task?.cancel()
        task = nil
        commandTask?.cancel()
        commandTask = nil
        commandSink.finish()
        helpers.terminateAll()
    }

    func send(_ command: PlaybackCommand) {
        commandSink.yield(command)
    }
}
