import Foundation
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

private final class ReadFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var wasRead: Bool { lock.withLock { value } }
    func mark() { lock.withLock { value = true } }
}

/// Records whether `updates` was ever read.
private struct WatchedProvider: NowPlayingProvider {
    let flag = ReadFlag()
    let checking = ReadFlag()
    var updates: AsyncStream<NowPlayingInfo?> {
        flag.mark()
        return AsyncStream { $0.finish() }
    }
    func isAvailable() async -> Bool {
        checking.mark()
        // Cancellation ends the sleep early, so the run is cancelled while choosing.
        try? await Task.sleep(for: .seconds(5))
        return true
    }
    func send(_ command: PlaybackCommand) async {}
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
        // Wait on the clock, not on a number of yields: choosing a provider hops executors.
        let deadline = ContinuousClock.now + .seconds(5)
        while !service.hasActiveProvider, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(service.hasActiveProvider)

        await service.send(.next)

        #expect(await active.log.commands == [.next])
        #expect(await idle.log.commands.isEmpty)

        running.cancel()
        continuation.finish()
        await running.value
    }

    @Test func cancelledRunStartsNoProvider() async {
        let provider = WatchedProvider()
        let service = NowPlayingService(providers: [provider], onUpdate: { _ in })

        let running = Task { await service.run() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !provider.checking.wasRead, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        running.cancel()
        await running.value

        #expect(!provider.flag.wasRead)
    }
}
