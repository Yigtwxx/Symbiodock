import Foundation

/// One subagent of a session.
public struct AgentSubagent: Identifiable, Equatable, Sendable {
    /// The tool's own id for the subagent.
    public let id: String
    public let title: String
    public let isFinished: Bool
    /// When it started while it works; when it finished once it is done.
    public let since: Date

    public init(id: String, title: String, isFinished: Bool, since: Date) {
        self.id = id
        self.title = title
        self.isFinished = isFinished
        self.since = since
    }
}

/// A line below a session's row.
public enum AgentBranch: Identifiable, Equatable, Sendable {
    case subagent(AgentSubagent)
    /// The subagents that did not fit.
    case more(Int)

    public var id: String {
        switch self {
        case .subagent(let subagent): "s:\(subagent.id)"
        case .more: "more"
        }
    }
}

/// Which subagents a row shows below itself, and in what order.
public enum AgentBranches {
    /// The most lines below one row.
    public static let maximumLines = 3

    /// A subagent that finished this long before the turn began still counts for the turn:
    /// its notification is what started the turn.
    public static let finishedGrace: TimeInterval = 10

    /// Working subagents, oldest first; then, while the parent works or waits, the ones
    /// that finished during its current turn (or just before it, `finishedGrace`), newest
    /// first. More than `maximumLines`:
    /// the first lines and a count of the rest.
    public static func lines(
        for subagents: [AgentSubagent], state: AgentRowState, turnStart: Date?
    ) -> [AgentBranch] {
        let working = subagents
            .filter { !$0.isFinished }
            .sorted { ($0.since, $0.id) < ($1.since, $1.id) }
        var finished: [AgentSubagent] = []
        if let turnStart, isActive(state) {
            finished = subagents
                .filter { $0.isFinished && $0.since >= turnStart.addingTimeInterval(-finishedGrace) }
                .sorted { $0.since != $1.since ? $0.since > $1.since : $0.id < $1.id }
        }
        let shown = working + finished
        guard shown.count > maximumLines else { return shown.map(AgentBranch.subagent) }
        let kept = maximumLines - 1
        let lines: [AgentBranch] = shown.prefix(kept).map(AgentBranch.subagent)
        return lines + [.more(shown.count - kept)]
    }

    private static func isActive(_ state: AgentRowState) -> Bool {
        switch state {
        case .working, .needsInput: true
        case .finished, .running, .idle: false
        }
    }
}
