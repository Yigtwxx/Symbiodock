/// Picks a provider and publishes the current track.
///
/// Providers are tried in order. The first available one is used until its stream
/// ends, which counts as a failure; then the next provider that has not failed is tried.
@MainActor
public final class NowPlayingService {
    private let providers: [any NowPlayingProvider]
    private let onUpdate: @MainActor (NowPlayingInfo?) -> Void
    private var active: (any NowPlayingProvider)?
    private var hasPublished = false
    private var lastPublished: NowPlayingInfo?

    public init(
        providers: [any NowPlayingProvider],
        onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void
    ) {
        self.providers = providers
        self.onUpdate = onUpdate
    }

    public var hasActiveProvider: Bool { active != nil }

    /// Runs until every provider has failed or is unavailable, or the task is cancelled.
    public func run() async {
        var failed: Set<Int> = []
        while !Task.isCancelled {
            var chosen: Int?
            for index in providers.indices where !failed.contains(index) {
                if await providers[index].isAvailable() {
                    chosen = index
                    break
                }
            }
            guard let chosen else { break }
            // Reading `updates` can start a process; do not do that for a cancelled run.
            if Task.isCancelled { break }

            active = providers[chosen]
            for await info in providers[chosen].updates {
                publish(info)
            }
            active = nil
            failed.insert(chosen)
            publish(nil)
        }
        publish(nil)
    }

    public func send(_ command: PlaybackCommand) async {
        await active?.send(command)
    }

    private func publish(_ info: NowPlayingInfo?) {
        guard !hasPublished || info != lastPublished else { return }
        hasPublished = true
        lastPublished = info
        onUpdate(info)
    }
}
