import Foundation
import Observation
import SymbiodockCore
import os

/// Measures this Mac while the System tab is on screen, and only then: every two seconds,
/// off the main thread, and hands each snapshot to the app.
@MainActor
final class SystemCoordinator {
    /// Numbers only.
    /// `log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "system"'`
    private static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "system")
    private static let interval: Duration = .seconds(2)
    /// Use and speed need two readings; the second follows the first quickly.
    private static let primingInterval: Duration = .milliseconds(500)
    /// The temperatures are read with every third reading: every six seconds.
    private static let temperatureEvery = 3

    private let isWatching: @MainActor () -> Bool
    private let onUpdate: @MainActor (SystemSnapshot, NetworkHistory) -> Void
    private let reader = SystemReader()
    private var meter = SystemMeter()
    private var task: Task<Void, Never>?
    /// Tells the running loop from one that has been replaced.
    private var run = 0
    private var isStopped = true
    private var hasLogged = false

    /// - Parameter isWatching: whether the open island shows the System tab. It must read
    ///   observable state: the coordinator observes what it reads.
    init(
        isWatching: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor (SystemSnapshot, NetworkHistory) -> Void
    ) {
        self.isWatching = isWatching
        self.onUpdate = onUpdate
    }

    func start() {
        guard isStopped else { return }
        isStopped = false
        observe()
        refresh()
    }

    func stop() {
        isStopped = true
        endLoop()
    }

    /// Calls `refresh` whenever what `isWatching` read has changed.
    private func observe() {
        withObservationTracking {
            _ = isWatching()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isStopped else { return }
                self.observe()
                self.refresh()
            }
        }
    }

    private func refresh() {
        if isWatching() { beginLoop() } else { endLoop() }
    }

    private func beginLoop() {
        guard task == nil else { return }
        run += 1
        let mine = run
        task = Task { [weak self] in
            await self?.loop()
            self?.loopEnded(mine)
        }
    }

    private func endLoop() {
        task?.cancel()
        task = nil
    }

    private func loopEnded(_ id: Int) {
        if id == run { task = nil }
    }

    private func loop() async {
        var count = 0
        while !Task.isCancelled, isWatching() {
            let reading = await reader.read(withTemperatures: count % Self.temperatureEvery == 0)
            guard !Task.isCancelled else { return }
            count += 1
            let snapshot = meter.take(reading)
            if let snapshot {
                onUpdate(snapshot, meter.history)
                logOnce(snapshot)
            }
            try? await Task.sleep(for: snapshot == nil ? Self.primingInterval : Self.interval)
        }
    }

    /// Says once which measures this Mac gives.
    private func logOnce(_ snapshot: SystemSnapshot) {
        guard !hasLogged else { return }
        hasLogged = true
        Self.log.notice(
            """
            measuring: cpu \(snapshot.cpu != nil, privacy: .public) \
            gpu \(snapshot.gpu != nil, privacy: .public) \
            cpuTemp \(snapshot.temperatures.cpu != nil, privacy: .public) \
            gpuTemp \(snapshot.temperatures.gpu != nil, privacy: .public) \
            online \(snapshot.isOnline, privacy: .public)
            """)
    }
}
