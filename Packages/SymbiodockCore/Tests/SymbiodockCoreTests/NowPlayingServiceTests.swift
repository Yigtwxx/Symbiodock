import Testing
@testable import SymbiodockCore

private actor CommandLog {
    private(set) var commands: [PlaybackCommand] = []
    func record(_ command: PlaybackCommand) { commands.append(command) }
}

private struct FakeProvider: NowPlayingProvider {
    let available: Bool
    let updates: AsyncStream<NowPlayingInfo?>
    let log = CommandLog()

    /// A provider whose stream delivers `values` and then ends (a runtime failure).
    static func finishing(available: Bool = true, _ values: [NowPlayingInfo?]) -> FakeProvider {
        FakeProvider(available: available, updates: AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        })
    }

    func isAvailable() async -> Bool { available }
    func send(_ command: PlaybackCommand) async { await log.record(command) }
}

@MainActor
private final class Recorder {
    var updates: [NowPlayingInfo?] = []
}

@MainActor
struct NowPlayingServiceTests {
    let a = NowPlayingInfo(title: "A", artist: "", isPlaying: true, sourceName: "One")
    let b = NowPlayingInfo(title: "B", artist: "", isPlaying: true, sourceName: "Two")

    @Test func firstAvailableProviderIsUsedAndFailureFallsBack() async {
        let recorder = Recorder()
        let service = NowPlayingService(
            providers: [FakeProvider.finishing([a]), FakeProvider.finishing([b])],
            onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [a, nil, b, nil])
    }

    @Test func unavailableProviderIsSkipped() async {
        let recorder = Recorder()
        let service = NowPlayingService(
            providers: [FakeProvider.finishing(available: false, [a]), FakeProvider.finishing([b])],
            onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [b, nil])
    }

    @Test func noProviderMeansNothingIsPlaying() async {
        let recorder = Recorder()
        let service = NowPlayingService(providers: [], onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [nil])
        #expect(!service.hasActiveProvider)
    }

    @Test func repeatedIdenticalUpdatesArePublishedOnce() async {
        let recorder = Recorder()
        let service = NowPlayingService(
            providers: [FakeProvider.finishing([a, a, nil, nil, b])],
            onUpdate: { recorder.updates.append($0) })

        await service.run()

        #expect(recorder.updates == [a, nil, b, nil])
    }

    @Test func commandsGoToTheActiveProvider() async {
        let (stream, continuation) = AsyncStream<NowPlayingInfo?>.makeStream()
        let active = FakeProvider(available: true, updates: stream)
        let idle = FakeProvider.finishing([b])
        let service = NowPlayingService(providers: [active, idle], onUpdate: { _ in })

        let running = Task { await service.run() }
        for _ in 0..<1_000 where !service.hasActiveProvider { await Task.yield() }
        #expect(service.hasActiveProvider)

        await service.send(.next)

        #expect(await active.log.commands == [.next])
        #expect(await idle.log.commands.isEmpty)

        running.cancel()
        continuation.finish()
        await running.value
    }
}
