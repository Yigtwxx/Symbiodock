import Foundation
import SymbiodockCore

/// Builds the providers and keeps the Now Playing service running.
@MainActor
final class NowPlayingCoordinator {
    private let service: NowPlayingService
    private var task: Task<Void, Never>?

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
            providers.append(MediaRemoteProvider(paths: paths))
        }
        providers.append(appleMusic)
        service = NowPlayingService(providers: providers, onUpdate: onUpdate)
    }

    func start() {
        guard task == nil else { return }
        task = Task { await service.run() }
    }

    /// Cancelling ends the provider's stream, which terminates the helper process.
    func stop() {
        task?.cancel()
        task = nil
    }

    func send(_ command: PlaybackCommand) {
        Task { await service.send(command) }
    }
}
