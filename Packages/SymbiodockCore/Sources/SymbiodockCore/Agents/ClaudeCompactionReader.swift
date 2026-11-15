import Foundation

/// Tells from the end of a Claude Code transcript whether a manual `/compact` is under way.
/// Claude Code writes the records that describe a compaction when it ends; its start leaves
/// one mark: a file snapshot whose message is not written yet (2.1.325), or a plain
/// `/compact` user record (2.1.303–2.1.318). Spec:
/// `2026-11-15-finish-seal-and-compacting-design.md`, section 5.1.
public enum ClaudeCompactionReader {
    /// How much of the transcript's end is read; the mark is always among the last records.
    public static let tailSize = 64 * 1024
    /// How old a mark must be before it counts: a normal prompt's snapshot is followed by
    /// its user record within milliseconds.
    public static let settleTime: TimeInterval = 1

    /// The record types that say something about the conversation. Every other type
    /// (metadata, queue operations, types added later) is passed over.
    private static let telling: Set<String> = [
        "user", "assistant", "system", "attachment", "file-history-snapshot",
    ]

    /// When the compaction under way started; nil when the tail shows none. Walks the lines
    /// from the end; lines that are cut off or are not JSON are skipped.
    public static func compactionStart(inTail data: Data) -> Date? {
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String, telling.contains(type)
            else { continue }
            switch type {
            case "file-history-snapshot":
                // An update rewrites an older snapshot; it says nothing about a new message.
                if object["isSnapshotUpdate"] as? Bool == true { continue }
                guard let messageID = object["messageId"] as? String, !messageID.isEmpty else {
                    return nil
                }
                // Its message is already written: an ordinary snapshot.
                if mentions(uuid: messageID, in: data) { continue }
                guard let snapshot = object["snapshot"] as? [String: Any],
                      let stamp = snapshot["timestamp"] as? String
                else { return nil }
                return timestamp(stamp)
            case "user":
                guard let message = object["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/compact"),
                      let stamp = object["timestamp"] as? String
                else { return nil }
                return timestamp(stamp)
            default:
                return nil
            }
        }
        return nil
    }

    /// Whether a compaction that started at `start` counts at `now`.
    public static func isCompacting(start: Date, now: Date) -> Bool {
        now.timeIntervalSince(start) >= settleTime
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
