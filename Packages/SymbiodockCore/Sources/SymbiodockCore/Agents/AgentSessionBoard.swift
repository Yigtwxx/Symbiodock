import Foundation

/// What the island should draw attention to.
public enum AgentAttention: Equatable, Sendable {
    case none
    /// A session finished and has not been looked at yet.
    case finished
    /// A session waits for the user.
    case needsInput
}

/// A session's state as the island shows it: its activity, plus "finished and not yet seen".
public enum AgentRowState: Equatable, Sendable {
    case needsInput(prompt: String?)
    case working
    case finished
    case running
    case idle

    /// Lower sorts first.
    var rank: Int {
        switch self {
        case .needsInput: 0
        case .working: 1
        case .finished: 2
        case .running: 3
        case .idle: 4
        }
    }
}

public struct AgentRow: Identifiable, Equatable, Sendable {
    public let session: AgentSession
    public let state: AgentRowState
    public var id: String { session.id }
}

/// Turns the providers' sessions into what the island shows: an ordered list, and what
/// deserves attention. It remembers which sessions it saw working, so it can tell a
/// session that has just finished from one that was idle all along.
public struct AgentSessionBoard: Equatable, Sendable {
    public private(set) var rows: [AgentRow] = []
    /// Sessions that were working or waiting on the last update.
    private var activeIDs: Set<String> = []
    /// Sessions seen going from active to idle and not looked at since.
    private var finishedIDs: Set<String> = []

    public init() {}

    /// Replaces the list. Of sessions sharing an id, the first is kept.
    public mutating func update(_ sessions: [AgentSession]) {
        var seen = Set<String>()
        var active = Set<String>()
        var unique: [AgentSession] = []
        for session in sessions where seen.insert(session.id).inserted {
            unique.append(session)
            switch session.activity {
            case .working, .needsInput:
                active.insert(session.id)
                finishedIDs.remove(session.id)
            case .idle:
                if activeIDs.contains(session.id) { finishedIDs.insert(session.id) }
            case .running:
                finishedIDs.remove(session.id)
            }
        }
        finishedIDs.formIntersection(seen)
        activeIDs = active
        rebuild(from: unique)
    }

    /// Forgets every finished mark: the user has looked.
    public mutating func markSeen() {
        guard !finishedIDs.isEmpty else { return }
        finishedIDs.removeAll()
        rebuild(from: rows.map(\.session))
    }

    public var attention: AgentAttention {
        var result = AgentAttention.none
        for row in rows {
            switch row.state {
            case .needsInput: return .needsInput
            case .finished: result = .finished
            case .working, .running, .idle: break
            }
        }
        return result
    }

    /// The session the collapsed island speaks for, if any deserves it.
    public var lead: AgentRow? {
        guard let first = rows.first else { return nil }
        switch first.state {
        case .needsInput, .working, .finished: return first
        case .running, .idle: return nil
        }
    }

    /// Whether the collapsed island has something to show for the agents.
    public var hasFace: Bool { lead != nil }

    public var needsInputCount: Int {
        rows.count { if case .needsInput = $0.state { true } else { false } }
    }

    public var workingCount: Int { rows.count { $0.state == .working } }

    private mutating func rebuild(from sessions: [AgentSession]) {
        rows = sessions
            .map { AgentRow(session: $0, state: state(of: $0)) }
            .sorted { lhs, rhs in
                if lhs.state.rank != rhs.state.rank { return lhs.state.rank < rhs.state.rank }
                if lhs.session.since != rhs.session.since {
                    return lhs.session.since > rhs.session.since
                }
                return lhs.id < rhs.id
            }
    }

    private func state(of session: AgentSession) -> AgentRowState {
        switch session.activity {
        case .needsInput(let prompt): .needsInput(prompt: prompt)
        case .working: .working
        case .running: .running
        case .idle: finishedIDs.contains(session.id) ? .finished : .idle
        }
    }
}
