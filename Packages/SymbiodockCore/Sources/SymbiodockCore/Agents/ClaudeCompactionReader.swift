import Foundation

/// What the transcript's end says about a manual compaction.
public enum CompactionMark: Equatable, Sendable {
    /// One is under way since this moment (its start mark).
    case started(Date)
    /// One ended at this moment (its boundary); the session file still says `busy` for a
    /// moment after it.
    case ended(Date)
}

/// Tells from the end of a Claude Code transcript whether a manual `/compact` is under way.
/// Claude Code writes the records that describe a compaction when it ends; its start leaves
/// one mark: a file snapshot whose message is not written yet (2.1.325), or a plain
/// `/compact` user record (2.1.303–2.1.318). Spec:
/// `2026-11-15-finish-seal-and-compacting-design.md`, section 5.1.
public enum ClaudeCompactionReader {
    /// How much of the transcript's end is read. The records after a manual compaction's
    /// boundary measured 312–441 KB (11 compactions, 2026-11-16), so a smaller tail never
    /// reaches the boundary and the end rule never fires. The start mark is always near the
    /// end, so a normal turn still stops after a line or two.
    public static let tailSize = 1024 * 1024
    /// How old a mark must be before it counts: a normal prompt's snapshot is followed by
    /// its user record within milliseconds.
    public static let settleTime: TimeInterval = 1

    /// The record types that say something about the conversation. Every other type
    /// (metadata, queue operations, types added later) is passed over.
    private static let telling: Set<String> = [
        "user", "assistant", "system", "attachment", "file-history-snapshot",
    ]

    /// How long after a manual compaction's boundary a busy session still counts as
    /// compacting: long enough to cover the moment before the session file turns idle, so
    /// that the end of a compaction is never taken for a finish.
    public static let endGrace: TimeInterval = 5

    /// What the tail shows about a manual compaction; nil when it shows none. Walks the lines
    /// from the end; lines that are cut off or are not JSON are skipped.
    public static func compactionMark(inTail data: Data) -> CompactionMark? {
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String, telling.contains(type)
            else { continue }
            switch type {
            case "attachment":
                // Attachments follow both prompts and compactions.
                continue
            case "system":
                guard object["subtype"] as? String == "compact_boundary",
                      let metadata = object["compactMetadata"] as? [String: Any],
                      metadata["trigger"] as? String == "manual",
                      let stamp = object["timestamp"] as? String,
                      let date = timestamp(stamp)
                else { return nil }
                return .ended(date)
            case "file-history-snapshot":
                // An update rewrites an older snapshot; it says nothing about a new message.
                if object["isSnapshotUpdate"] as? Bool == true { continue }
                guard let messageID = object["messageId"] as? String, !messageID.isEmpty else {
                    return nil
                }
                // Its message is already written: an ordinary snapshot.
                if mentions(uuid: messageID, in: data) { continue }
                guard let snapshot = object["snapshot"] as? [String: Any],
                      let stamp = snapshot["timestamp"] as? String,
                      let date = timestamp(stamp)
                else { return nil }
                return .started(date)
            case "user":
                if isBookkeeping(object) { continue }
                guard let message = object["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/compact"),
                      let stamp = object["timestamp"] as? String,
                      let date = timestamp(stamp)
                else { return nil }
                return .started(date)
            default:
                return nil
            }
        }
        return nil
    }

    /// Whether the mark counts at `now`: a start once it has settled, an end for a short
    /// while after its boundary.
    public static func isCompacting(_ mark: CompactionMark, now: Date) -> Bool {
        switch mark {
        case .started(let start): now.timeIntervalSince(start) >= settleTime
        case .ended(let end): now.timeIntervalSince(end) < endGrace
        }
    }

    /// A user record Claude Code writes around a compaction, not something the user typed.
    private static func isBookkeeping(_ object: [String: Any]) -> Bool {
        if object["isMeta"] as? Bool == true || object["isCompactSummary"] as? Bool == true {
            return true
        }
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return false }
        return content.hasPrefix("<local-command-stdout>") || content.hasPrefix("<command-name>/compact")
    }

    /// Whether a record in the tail has this uuid. Claude Code writes compact JSON, so the
    /// key and its value sit side by side.
    private static func mentions(uuid: String, in data: Data) -> Bool {
        data.range(of: Data("\"uuid\":\"\(uuid)\"".utf8)) != nil
    }

    /// "2026-11-15T20:42:20.696Z", with or without the fraction.
    private static func timestamp(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
