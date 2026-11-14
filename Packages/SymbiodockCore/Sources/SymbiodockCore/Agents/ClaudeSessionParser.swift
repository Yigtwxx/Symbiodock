import Foundation

/// The fields Symbiodock reads from a Claude Code session file.
public struct ClaudeSessionRecord: Equatable, Sendable {
    public let pid: Int32
    public let sessionID: String?
    public let cwd: String?
    public let name: String?
    /// "busy", "idle", "waiting", or something newer.
    public let status: String?
    public let waitingFor: String?
    public let statusUpdatedAt: Date?
    /// A pre-warmed process that is not a session yet.
    public let isSpare: Bool
}

/// Reads `~/.claude/sessions/<pid>.json`, which Claude Code keeps for every running session.
public enum ClaudeSessionParser {
    public static let maximumFileSize = 64 * 1024

    public static func record(from data: Data) -> ClaudeSessionRecord? {
        guard data.count <= maximumFileSize,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = processID(object["pid"])
        else { return nil }
        let milliseconds = number(object["statusUpdatedAt"])
        return ClaudeSessionRecord(
            pid: pid,
            sessionID: object["sessionId"] as? String,
            cwd: object["cwd"] as? String,
            name: object["name"] as? String,
            status: object["status"] as? String,
            waitingFor: object["waitingFor"] as? String,
            statusUpdatedAt: milliseconds.flatMap { value in
                value > 0 && value < maximumMilliseconds ? Date(timeIntervalSince1970: value / 1000) : nil
            },
            isSpare: (object["spare"] as? Bool) == true)
    }

    /// About year 5138; anything larger is not a time.
    private static let maximumMilliseconds = 1e14

    /// A JSON number as a Double; a boolean is not a number here.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// A positive whole number that fits `Int32`; nil for anything else, so a huge value
    /// is rejected instead of wrapping around to a valid-looking pid.
    private static func processID(_ value: Any?) -> Int32? {
        guard let double = number(value), double >= 1, double <= Double(Int32.max),
              double == double.rounded()
        else { return nil }
        return Int32(double)
    }

    /// The session a record stands for; nil for a spare process.
    /// - Parameter prompt: the open question, if one was read from the transcript.
    /// - Parameter fallbackSince: used when the file does not say when the status began.
    public static func session(
        from record: ClaudeSessionRecord, prompt: String?, fallbackSince: Date
    ) -> AgentSession? {
        guard !record.isSpare else { return nil }
        let activity: AgentActivity =
            switch record.status {
            case "busy": .working
            case "idle": .idle
            case "waiting": .needsInput(prompt: prompt)
            default: .running
            }
        let name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = record.cwd.map { ($0 as NSString).lastPathComponent }
        let title = [name, folder].compactMap { $0 }.first { !$0.isEmpty && $0 != "/" }
        return AgentSession(
            id: "\(AgentTool.claudeCode.rawValue):\(record.pid)",
            tool: .claudeCode,
            title: title ?? AgentTool.claudeCode.displayName,
            projectPath: record.cwd,
            activity: activity,
            since: record.statusUpdatedAt ?? fallbackSince,
            pid: record.pid)
    }

    /// Where the session's transcript lies below `~/.claude`. Claude Code names the folder
    /// after the working directory, with everything but ASCII letters and digits as "-".
    /// Nil if either part is empty or the id could leave the folder.
    public static func transcriptRelativePath(cwd: String, sessionID: String) -> String? {
        guard !cwd.isEmpty, !sessionID.isEmpty,
              sessionID.unicodeScalars.allSatisfy({ isLetterOrDigit($0) || $0 == "-" })
        else { return nil }
        let slug = String(
            String.UnicodeScalarView(cwd.unicodeScalars.map { isLetterOrDigit($0) ? $0 : "-" }))
        return "projects/\(slug)/\(sessionID).jsonl"
    }

    private static func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9": true
        default: false
        }
    }
}
