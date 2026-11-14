import Foundation

/// What a Codex rollout file says about its thread in its first line.
public struct CodexThreadMeta: Equatable, Sendable {
    public let id: String
    public let cwd: String?
    /// A thread spawned by another thread; it is not shown on its own.
    public let isSubagent: Bool
    /// "Codex Desktop", ...
    public let originator: String?

    public init(id: String, cwd: String?, isSubagent: Bool, originator: String?) {
        self.id = id
        self.cwd = cwd
        self.isSubagent = isSubagent
        self.originator = originator
    }
}

/// Whether a Codex thread is in the middle of a turn, and since when.
public struct CodexTurnState: Equatable, Sendable {
    public let isWorking: Bool
    public let since: Date

    public init(isWorking: Bool, since: Date) {
        self.isWorking = isWorking
        self.since = since
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
        let parent = payload["parent_thread_id"] as? String
        let source = payload["source"] as? [String: Any]
        return CodexThreadMeta(
            id: id,
            cwd: payload["cwd"] as? String,
            isSubagent: !(parent ?? "").isEmpty || source?["subagent"] != nil,
            originator: payload["originator"] as? String)
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
            state = CodexTurnState(isWorking: type == "task_started", since: date)
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

    /// "2026-11-14T18:45:26.561Z", with or without the fraction.
    static func timestamp(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
