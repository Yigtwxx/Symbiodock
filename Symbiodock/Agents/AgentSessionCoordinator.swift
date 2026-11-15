import Foundation
import SymbiodockCore
import os

/// Asks the providers for their sessions again and again, off the main thread, and hands
/// the merged list to the app.
@MainActor
final class AgentSessionCoordinator {
    /// Counts and tool names only; never a title, a path or a question.
    private static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "agents")
    /// Seconds between scans while nobody looks at the Agents tab.
    private static let restingInterval = 3

    private let providers: [any AgentSessionProvider]
    private let wakeFolders: [URL]
    private let isWatching: @MainActor () -> Bool
    private let onUpdate: @MainActor ([AgentSession]) -> Void
    private let signal = ScanSignal()
    private var watchers: [SessionFolderWatcher] = []
    private var task: Task<Void, Never>?

    /// - Parameter wakeFolders: folders whose changes start a scan at once.
    /// - Parameter isWatching: whether the Agents tab is on screen; then the scan runs every second.
    init(
        providers: [any AgentSessionProvider],
        wakeFolders: [URL] = [],
        isWatching: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor ([AgentSession]) -> Void
    ) {
        self.providers = providers
        self.wakeFolders = wakeFolders
        self.isWatching = isWatching
        self.onUpdate = onUpdate
    }

    func start() {
        guard task == nil else { return }
        let providers = providers
        let scanner = ProcessScanner()
        let signal = signal
        watchers = wakeFolders.map { SessionFolderWatcher(folder: $0) { signal.fire() } }
        task = Task { [weak self] in
            var lastCount = -1
            var lastStart: Date?
            while !Task.isCancelled {
                // However often it is woken, two scans never start too close together.
                let gap = ScanPacing.delay(sinceLastStart: lastStart, now: Date())
                if gap > 0 { try? await Task.sleep(for: .seconds(gap)) }
                lastStart = Date()
                // A folder that did not exist yet may have appeared since.
                self?.watchers.forEach { $0.start() }
                // One scan at a time: the next starts only after this one has ended.
                let sessions = await Self.scan(providers, with: scanner)
                guard !Task.isCancelled, let self else { return }
                self.onUpdate(sessions)
                if sessions.count != lastCount {
                    lastCount = sessions.count
                    let tools = Set(sessions.map(\.tool.rawValue)).sorted().joined(separator: ",")
                    Self.log.notice("sessions: \(sessions.count, privacy: .public) [\(tools, privacy: .public)]")
                }
                // Until the next scan is due. A changed session file, or the Agents tab
                // being looked at, ends the wait early.
                for _ in 0..<Self.restingInterval {
                    if await signal.wait(upTo: .seconds(1)) { break }
                    if Task.isCancelled || self.isWatching() { break }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        watchers.forEach { $0.stop() }
        watchers = []
        // Ends a wait at once, so that the cancelled loop returns now.
        signal.fire()
    }

    /// Runs off the main actor: it reads files and the process list.
    nonisolated private static func scan(
        _ providers: [any AgentSessionProvider], with scanner: ProcessScanner
    ) async -> [AgentSession] {
        let processes = await scanner.snapshot()
        let context = AgentScanContext(now: Date(), processes: processes)
        var sessions: [AgentSession] = []
        for provider in providers {
            sessions += await provider.sessions(in: context)
        }
        return sessions.map { HostApp.resolving($0, in: processes) }
    }
}
