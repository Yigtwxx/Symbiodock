import Foundation
import SymbiodockCore

/// Builds the providers and keeps the Now Playing service running.
@MainActor
final class NowPlayingCoordinator {
    private let service: NowPlayingService
    private var task: Task<Void, Never>?

    init(onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void) {
        var providers: [any NowPlayingProvider] = []
        if let paths = MediaRemoteProvider.Paths.inMainBundle() {
            providers.append(MediaRemoteProvider(paths: paths))
        }
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
