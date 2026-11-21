import Foundation
import Observation
import SymbiodockCore
import os

/// Measures this Mac while the System tab is on screen, and only then: every two seconds,
/// off the main thread, and hands each snapshot to the app. While the tab is shown it also
/// reads the devices the Mac already knows, and it runs a scan of the network when one was
/// asked for. Nothing is sent to the network unless a scan was asked for.
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
    /// The known devices are read with every fifth reading: every ten seconds.
    private static let devicesEvery = 5

    private let isWatching: @MainActor () -> Bool
    private let isScanRequested: @MainActor () -> Bool
    private let onUpdate: @MainActor (SystemSnapshot, NetworkHistory) -> Void
    private let onDevices: @MainActor ([LANDevice], Bool) -> Void
    private let onScanEnd: @MainActor (Bool) -> Void
    private let reader = SystemReader()
    private let scanner = LANScanner()
    private var meter = SystemMeter()
    private var task: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    /// Tells the running loop from one that has been replaced.
    private var run = 0
    private var isStopped = true
    private var hasLogged = false

    /// - Parameter isWatching: whether the open island shows the System tab.
    /// - Parameter isScanRequested: whether a scan was asked for and has not ended.
    ///   Both must read observable state: the coordinator observes what they read.
    /// - Parameter onDevices: the devices known now, and whether this network can be scanned.
    /// - Parameter onScanEnd: the scan has ended; true when macOS kept it back.
    init(
        isWatching: @escaping @MainActor () -> Bool,
        isScanRequested: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor (SystemSnapshot, NetworkHistory) -> Void,
        onDevices: @escaping @MainActor ([LANDevice], Bool) -> Void,
        onScanEnd: @escaping @MainActor (Bool) -> Void
    ) {
        self.isWatching = isWatching
        self.isScanRequested = isScanRequested
        self.onUpdate = onUpdate
        self.onDevices = onDevices
        self.onScanEnd = onScanEnd
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
        scanTask?.cancel()
        scanTask = nil
    }

    /// Calls `refresh` whenever what `isWatching` read has changed.
    private func observe() {
        withObservationTracking {
            _ = isWatching()
            _ = isScanRequested()
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
        if isScanRequested() { beginScan() }
    }

    /// Runs the scan that was asked for. It is short, and it finishes even if the tab is left
    /// meanwhile: the state waits for its end.
    private func beginScan() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            guard let scanner = self?.scanner else { return }
            let result = await scanner.scan()
            guard let self, !Task.isCancelled else { return }
            self.onDevices(result.devices, result.canScan)
            self.onScanEnd(result.isBlocked)
            Self.log.notice(
                "scan: \(result.devices.count, privacy: .public) devices, blocked \(result.isBlocked, privacy: .public)")
            self.scanTask = nil
        }
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
            if count % Self.devicesEvery == 0, scanTask == nil {
                let known = await scanner.known()
                guard !Task.isCancelled else { return }
                // A scan that began meanwhile brings a fuller list itself.
                if scanTask == nil { onDevices(known.devices, known.canScan) }
            }
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
