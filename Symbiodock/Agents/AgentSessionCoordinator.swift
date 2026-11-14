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
    private let isWatching: @MainActor () -> Bool
    private let onUpdate: @MainActor ([AgentSession]) -> Void
    private var task: Task<Void, Never>?

    /// - Parameter isWatching: whether the Agents tab is on screen; then the scan runs every second.
    init(
        providers: [any AgentSessionProvider],
        isWatching: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor ([AgentSession]) -> Void
    ) {
        self.providers = providers
        self.isWatching = isWatching
        self.onUpdate = onUpdate
    }

    func start() {
        guard task == nil else { return }
        let providers = providers
        task = Task { [weak self] in
            var lastCount = -1
            while !Task.isCancelled {
                // One scan at a time: the next starts only after this one has ended.
                let sessions = await Self.scan(providers)
                guard !Task.isCancelled, let self else { return }
                self.onUpdate(sessions)
                if sessions.count != lastCount {
                    lastCount = sessions.count
                    let tools = Set(sessions.map(\.tool.rawValue)).sorted().joined(separator: ",")
                    Self.log.notice("sessions: \(sessions.count, privacy: .public) [\(tools, privacy: .public)]")
                }
                // Wake early as soon as the Agents tab is being looked at.
                for _ in 0..<Self.restingInterval {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled || self.isWatching() { break }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Runs off the main actor: it reads files and the process list.
    nonisolated private static func scan(
        _ providers: [any AgentSessionProvider]
    ) async -> [AgentSession] {
        let context = AgentScanContext(now: Date(), processes: ProcessScanner.snapshot())
        var sessions: [AgentSession] = []
        for provider in providers {
            sessions += await provider.sessions(in: context)
        }
        return sessions
    }
}
