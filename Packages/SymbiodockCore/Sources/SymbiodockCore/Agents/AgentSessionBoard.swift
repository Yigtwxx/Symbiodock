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
    case compacting
    case finished
    case running
    case idle

    /// Lower sorts first. A finish leads until it has played its seal (`settled`), then it
    /// steps back behind the sessions that are still at work.
    func rank(settled: Bool) -> Int {
        switch self {
        case .needsInput: 0
        case .finished: settled ? 3 : 1
        case .working, .compacting: 2
        case .running: 4
        case .idle: 5
        }
    }
}

public struct AgentRow: Identifiable, Equatable, Sendable {
    public let session: AgentSession
    public let state: AgentRowState
    /// A finish that has played its seal: still `Done ✓` in the list, but it no longer
    /// leads the collapsed island or draws attention. Always false for other states.
    public let isSettled: Bool
    /// The lines below the row: its subagents.
    public let branches: [AgentBranch]
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
    /// Finished sessions whose seal has played; always a subset of `finishedIDs`.
    private var settledIDs: Set<String> = []
    /// When each active session's current turn began: its `since` on the update where it
    /// became active. A question in the middle of the turn does not move it.
    private var turnStarts: [String: Date] = [:]

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
                settledIDs.remove(session.id)
                if !activeIDs.contains(session.id) || turnStarts[session.id] == nil {
                    turnStarts[session.id] = session.since
                }
            case .compacting:
                // Not a turn: what showed as finished is not, and its end will not be.
                finishedIDs.remove(session.id)
                settledIDs.remove(session.id)
            case .idle:
                if activeIDs.contains(session.id) { finishedIDs.insert(session.id) }
            case .running:
                finishedIDs.remove(session.id)
                settledIDs.remove(session.id)
            }
        }
        finishedIDs.formIntersection(seen)
        settledIDs.formIntersection(finishedIDs)
        turnStarts = turnStarts.filter { active.contains($0.key) }
        activeIDs = active
        rebuild(from: unique)
    }

    /// Forgets every finished mark: the user has looked.
    public mutating func markSeen() {
        guard !finishedIDs.isEmpty else { return }
        finishedIDs.removeAll()
        settledIDs.removeAll()
        rebuild(from: rows.map(\.session))
    }

    /// A finished session has played its seal: it stays `Done ✓` in the list until
    /// `markSeen`, but no longer leads, draws attention or gives the island a face.
    /// Ignored for a session that is not finished, or already settled.
    public mutating func settle(_ id: String) {
        guard finishedIDs.contains(id), settledIDs.insert(id).inserted else { return }
        rebuild(from: rows.map(\.session))
    }

    /// A finish that has not been looked at yet, settled or not: the list keeps `Done ✓`
    /// for it until `markSeen`.
    public var hasUnseenFinish: Bool { !finishedIDs.isEmpty }

    public var attention: AgentAttention {
        var result = AgentAttention.none
        for row in rows {
            switch row.state {
            case .needsInput: return .needsInput
            case .finished where !row.isSettled: result = .finished
            case .working, .compacting, .finished, .running, .idle: break
            }
        }
        return result
    }

    /// The session the collapsed island speaks for, if any deserves it.
    public var lead: AgentRow? {
        guard let first = rows.first else { return nil }
        switch first.state {
        case .needsInput, .working, .compacting: return first
        case .finished: return first.isSettled ? nil : first
        case .running, .idle: return nil
        }
    }

    /// Who speaks for the agents on a docked island: the lead, or else the first row, so
    /// that a list that is not empty is never described as "no agents". Nil only when the
    /// list is empty.
    public var spokesperson: AgentRow? { lead ?? rows.first }

    /// The session behind `attention`: the first that needs input, else the first finish that has not settled.
    public var attentionRow: AgentRow? {
        rows.first { if case .needsInput = $0.state { true } else { false } }
            ?? rows.first { $0.state == .finished && !$0.isSettled }
    }

    /// Whether the collapsed island has something to show for the agents.
    public var hasFace: Bool { lead != nil }

    public var needsInputCount: Int {
        rows.count { if case .needsInput = $0.state { true } else { false } }
    }

    public var workingCount: Int { rows.count { $0.state == .working } }

    private mutating func rebuild(from sessions: [AgentSession]) {
        rows = sessions
            .map { session in
                let state = state(of: session)
                return AgentRow(
                    session: session, state: state,
                    isSettled: state == .finished && settledIDs.contains(session.id),
                    branches: AgentBranches.lines(
                        for: session.subagents, state: state, turnStart: turnStarts[session.id]))
            }
            .sorted { lhs, rhs in
                let left = lhs.state.rank(settled: lhs.isSettled)
                let right = rhs.state.rank(settled: rhs.isSettled)
                if left != right { return left < right }
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
        case .compacting: .compacting
        case .running: .running
        case .idle: finishedIDs.contains(session.id) ? .finished : .idle
        }
    }
}
