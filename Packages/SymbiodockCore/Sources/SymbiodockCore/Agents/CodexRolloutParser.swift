import Foundation

/// What a Codex rollout file says about its thread in its first line.
public struct CodexThreadMeta: Equatable, Sendable {
    public let id: String
    public let cwd: String?
    /// A thread spawned by another thread; it is shown as a branch of its parent.
    public let isSubagent: Bool
    /// "Codex Desktop", ...
    public let originator: String?
    /// The thread that spawned this one.
    public let parentID: String?
    /// A subagent's name, from its agent path or nickname.
    public let subagentTitle: String?
    /// When the thread was created.
    public let started: Date?

    public init(
        id: String, cwd: String?, isSubagent: Bool, originator: String?,
        parentID: String? = nil, subagentTitle: String? = nil, started: Date? = nil
    ) {
        self.id = id
        self.cwd = cwd
        self.isSubagent = isSubagent
        self.originator = originator
        self.parentID = parentID
        self.subagentTitle = subagentTitle
        self.started = started
    }
}

/// Whether a Codex thread is in the middle of a turn, and since when.
public struct CodexTurnState: Equatable, Sendable {
    public let isWorking: Bool
    public let since: Date
    /// The last turn was stopped rather than completed.
    public let wasAborted: Bool

    public init(isWorking: Bool, since: Date, wasAborted: Bool = false) {
        self.isWorking = isWorking
        self.since = since
        self.wasAborted = wasAborted
    }
}

/// Reads `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, one JSON object per line.
public enum CodexRolloutParser {
    /// The first line is about 22 KB; this leaves room.
    public static let headSize = 1024 * 1024
    public static let tailSize = 256 * 1024
    /// An idle thread is listed this long after its file last changed.
    public static let idleListing: TimeInterval = 30 * 60
    /// A turn whose file has not changed for this long is taken for abandoned.
    public static let workingListing: TimeInterval = 2 * 60 * 60
    /// A working subagent whose file has not changed for this long is taken for abandoned.
    public static let subagentQuietLimit: TimeInterval = 10 * 60

    private static let turnEvents: Set<String> = ["task_started", "task_complete", "turn_aborted"]
    private static let turnMarkers = turnEvents.map { Data("\"\($0)\"".utf8) }

    /// The thread described by the file's first line; nil if it is not a `session_meta` line.
    public static func meta(fromHead data: Data) -> CodexThreadMeta? {
        guard let line = data.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = payload["id"] as? String, !id.isEmpty
        else { return nil }
        let source = payload["source"] as? [String: Any]
        let spawn = (source?["subagent"] as? [String: Any])?["thread_spawn"] as? [String: Any]
        let parent = [spawn?["parent_thread_id"], payload["parent_thread_id"]]
            .compactMap { $0 as? String }
            .first { !$0.isEmpty }
        let stamp = (payload["timestamp"] as? String) ?? (object["timestamp"] as? String)
        return CodexThreadMeta(
            id: id,
            cwd: payload["cwd"] as? String,
            isSubagent: parent != nil || source?["subagent"] != nil,
            originator: payload["originator"] as? String,
            parentID: parent,
            subagentTitle: subagentTitle(spawn),
            started: stamp.flatMap(timestamp))
    }

    /// "/root/notch_market_research" -> "notch market research"; else the nickname.
    static func subagentTitle(_ spawn: [String: Any]?) -> String? {
        guard let spawn else { return nil }
        if let path = spawn["agent_path"] as? String {
            let name = (path as NSString).lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && name != "/" { return name }
        }
        let nickname = (spawn["agent_nickname"] as? String)?.trimmingCharacters(in: .whitespaces)
        return nickname?.isEmpty == false ? nickname : nil
    }

    /// The last turn event in the end of the file; nil if there is none with a readable time.
    public static func turnState(inTail data: Data) -> CodexTurnState? {
        var state: CodexTurnState?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            // Most lines are model output; parse only the ones that can be turn events.
            guard turnMarkers.contains(where: { line.range(of: $0) != nil }),
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let type = payload["type"] as? String, turnEvents.contains(type),
                  let stamp = object["timestamp"] as? String, let date = timestamp(stamp)
            else { continue }
            state = CodexTurnState(
                isWorking: type == "task_started", since: date, wasAborted: type == "turn_aborted")
        }
        return state
    }

    /// Whether a thread in this state, whose file last changed at `modified`, is still shown.
    public static func isListed(_ state: CodexTurnState, modified: Date, now: Date) -> Bool {
        now.timeIntervalSince(modified) <= (state.isWorking ? workingListing : idleListing)
    }

    public static func session(
        meta: CodexThreadMeta, state: CodexTurnState, title: String?, pid: Int32?
    ) -> AgentSession {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = meta.cwd.map { ($0 as NSString).lastPathComponent }
        let shown = [name, folder].compactMap { $0 }.first { !$0.isEmpty && $0 != "/" }
        return AgentSession(
            id: "\(AgentTool.codex.rawValue):\(meta.id)",
            tool: .codex,
            title: shown ?? AgentTool.codex.displayName,
            projectPath: meta.cwd,
            activity: state.isWorking ? .working : .idle,
            since: state.since,
            pid: pid)
    }

    /// A subagent as its parent's branch, or nil if it is not shown: it was stopped, it
    /// went quiet in the middle of a turn, or it finished long ago.
    public static func subagent(
        meta: CodexThreadMeta, state: CodexTurnState, modified: Date, now: Date
    ) -> AgentSubagent? {
        guard meta.isSubagent, !state.wasAborted else { return nil }
        let title = meta.subagentTitle ?? "Subagent"
        if state.isWorking {
            guard now.timeIntervalSince(modified) <= subagentQuietLimit else { return nil }
            return AgentSubagent(id: meta.id, title: title, isFinished: false, since: meta.started ?? state.since)
        }
        guard now.timeIntervalSince(modified) <= idleListing else { return nil }
        return AgentSubagent(id: meta.id, title: title, isFinished: true, since: state.since)
    }

    /// The listed thread a subagent descends from, following `parents` (thread id ->
    /// parent id); nil if none of its ancestors is listed.
    public static func rootID(
        of id: String, parents: [String: String], listed: Set<String>
    ) -> String? {
        var current = id
        var seen: Set<String> = [id]
        while let parent = parents[current] {
            if listed.contains(parent) { return parent }
            guard seen.insert(parent).inserted else { return nil }
            current = parent
        }
        return nil
    }

    /// "2026-11-14T18:45:26.561Z", with or without the fraction.
    static func timestamp(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
