import Darwin
import Foundation
import SymbiodockCore

/// Claude Code keeps one small JSON file per running session in `~/.claude/sessions`,
/// with its name, folder and whether it is busy, idle or waiting for the user.
actor ClaudeCodeProvider: AgentSessionProvider {
    nonisolated let tool = AgentTool.claudeCode
    /// `~/.claude`
    private let home: URL

    /// What was read from a waiting session's transcript, until the file changes.
    private struct Asked {
        let stamp: FileStamp
        let question: String?
    }

    private var asked: [String: Asked] = [:]

    init(home: URL) {
        self.home = home
    }

    func sessions(in context: AgentScanContext) async -> [AgentSession] {
        let directory = home.appendingPathComponent("sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        else {
            asked.removeAll()
            return []
        }

        var stillAsking: [String: Asked] = [:]
        defer { asked = stillAsking }
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let stamp = FileReading.stamp(of: url),
                  let data = FileReading.whole(url, maxBytes: ClaudeSessionParser.maximumFileSize),
                  let record = ClaudeSessionParser.record(from: data),
                  Self.isAlive(record.pid)
            else { return nil }
            return ClaudeSessionParser.session(
                from: record,
                prompt: record.status == "waiting" ? question(of: record, remembering: &stillAsking) : nil,
                fallbackSince: stamp.modified)
        }
    }

    /// The question the session is waiting on, if its transcript shows one. The transcript
    /// is read again only when its size or modification time changed; `remembering`
    /// collects what is still in use, so that the questions of sessions that are gone are
    /// forgotten.
    private func question(
        of record: ClaudeSessionRecord, remembering kept: inout [String: Asked]
    ) -> String? {
        guard let cwd = record.cwd, let sessionID = record.sessionID,
              let path = ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
        else { return nil }
        let url = home.appendingPathComponent(path)
        guard let stamp = FileReading.stamp(of: url) else { return nil }
        if let known = asked[path], known.stamp == stamp {
            kept[path] = known
            return known.question
        }
        let question = FileReading.tail(of: url, maxBytes: ClaudeTranscriptPromptReader.tailSize)
            .flatMap(ClaudeTranscriptPromptReader.pendingQuestion(inTail:))
        kept[path] = Asked(stamp: stamp, question: question)
        return question
    }

    /// A session file can outlive a process that was killed.
    private nonisolated static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
