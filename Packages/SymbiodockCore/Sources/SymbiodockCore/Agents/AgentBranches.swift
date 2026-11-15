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

    /// A subagent's own tone among `count`, from its id: FNV-1a, so the same in every run.
    public static func tone(of id: String, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    /// The tone of each line's dot. A subagent takes its own tone unless a line above has
    /// it; then the next free one, so that up to `count` lines never share a colour. The
    /// count line has none.
    public static func tones(for lines: [AgentBranch], count: Int) -> [Int?] {
        guard count > 0 else { return lines.map { _ in nil } }
        var taken = Set<Int>()
        return lines.map { line in
            guard case .subagent(let subagent) = line else { return nil }
            var pick = Self.tone(of: subagent.id, count: count)
            if taken.count < count {
                while taken.contains(pick) { pick = (pick + 1) % count }
            }
            taken.insert(pick)
            return pick
        }
    }

    private static func isActive(_ state: AgentRowState) -> Bool {
        switch state {
        case .working, .needsInput: true
        case .compacting, .finished, .running, .idle: false
        }
    }
}
