import Foundation

/// What a Claude Code subagent's meta file says.
public struct ClaudeSubagentMeta: Equatable, Sendable {
    public let title: String
    /// Written when it ends normally; absent while it runs and after it was stopped.
    public let isFinished: Bool
    /// The parent's `tool_use` that started it.
    public let toolUseID: String?
    /// Started in the background: its end is announced by a task notification.
    public let isBackground: Bool
}

/// Reads `~/.claude/projects/<slug>/<sessionId>/subagents/agent-<id>.meta.json` and the
/// signs in the parent's transcript that a subagent has ended.
public enum ClaudeSubagentParser {
    public static let maximumMetaSize = 16 * 1024
    /// A subagent that has not finished and whose transcript has been quiet this long
    /// has ended without saying so.
    public static let quietLimit: TimeInterval = 10 * 60
    /// A finished subagent older than this is not passed on.
    public static let finishedListing: TimeInterval = 2 * 60 * 60

    /// Below `~/.claude`, next to the session's transcript.
    public static func folderRelativePath(cwd: String, sessionID: String) -> String? {
        ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
            .map { String($0.dropLast(".jsonl".count)) + "/subagents" }
    }

    /// The id in `agent-<id>.meta.json`; nil for any other name, or an id that could
    /// leave the folder.
    public static func agentID(metaFileName name: String) -> String? {
        let prefix = "agent-", suffix = ".meta.json"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
              name.count > prefix.count + suffix.count
        else { return nil }
        let id = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard id.unicodeScalars.allSatisfy({ isLetterOrDigit($0) || $0 == "-" }) else { return nil }
        return id
    }

    public static func meta(from data: Data) -> ClaudeSubagentMeta? {
        guard data.count <= maximumMetaSize,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let title = [object["description"], object["agentType"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return ClaudeSubagentMeta(
            title: title ?? "Subagent",
            isFinished: (object["finished"] as? Bool) == true,
            toolUseID: object["toolUseId"] as? String,
            isBackground: object["requestShape"] as? String == "background")
    }

    /// The candidates the parent's transcript shows as ended: a task notification naming
    /// a background subagent, or a tool result answering the `tool_use` that started any
    /// other. (A background subagent's tool result comes at its launch.)
    public static func endedIDs(
        _ candidates: [(id: String, meta: ClaudeSubagentMeta)], inTail data: Data
    ) -> Set<String> {
        var ended = Set<String>()
        for (id, meta) in candidates {
            let marker: String
            if meta.isBackground {
                marker = "<task-id>\(id)</task-id>"
            } else if let toolUseID = meta.toolUseID, !toolUseID.isEmpty {
                marker = "\"tool_use_id\":\"\(toolUseID)\""
            } else {
                continue
            }
            if data.range(of: Data(marker.utf8)) != nil { ended.insert(id) }
        }
        return ended
    }

    /// The subagent as the island shows it, or nil once it is no longer shown.
    /// - Parameters:
    ///   - started: when its transcript was created, or its meta file without one.
    ///   - lastWrite: its transcript's last change.
    ///   - metaModified: its meta file's last change: the finish, once it has finished.
    ///   - hasEnded: the parent's transcript shows that it ended.
    public static func subagent(
        id: String, meta: ClaudeSubagentMeta, started: Date, lastWrite: Date,
        metaModified: Date, hasEnded: Bool, now: Date
    ) -> AgentSubagent? {
        if meta.isFinished {
            guard now.timeIntervalSince(metaModified) <= finishedListing else { return nil }
            return AgentSubagent(id: id, title: meta.title, isFinished: true, since: metaModified)
        }
        guard !hasEnded, now.timeIntervalSince(lastWrite) <= quietLimit else { return nil }
        return AgentSubagent(id: id, title: meta.title, isFinished: false, since: started)
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9": true
        default: false
        }
    }
}
