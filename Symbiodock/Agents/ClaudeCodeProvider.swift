import Darwin
import Foundation
import SymbiodockCore

/// Claude Code keeps one small JSON file per running session in `~/.claude/sessions`,
/// with its name, folder and whether it is busy, idle or waiting for the user.
struct ClaudeCodeProvider: AgentSessionProvider {
    let tool = AgentTool.claudeCode
    /// `~/.claude`
    let home: URL

    func sessions(in context: AgentScanContext) async -> [AgentSession] {
        let directory = home.appendingPathComponent("sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let stamp = FileReading.stamp(of: url),
                  let data = FileReading.whole(url, maxBytes: ClaudeSessionParser.maximumFileSize),
                  let record = ClaudeSessionParser.record(from: data),
                  Self.isAlive(record.pid)
            else { return nil }
            return ClaudeSessionParser.session(
                from: record,
                prompt: record.status == "waiting" ? question(of: record) : nil,
                fallbackSince: stamp.modified)
        }
    }

    /// The question the session is waiting on, if its transcript shows one.
    private func question(of record: ClaudeSessionRecord) -> String? {
        guard let cwd = record.cwd, let sessionID = record.sessionID,
              let path = ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID),
              let tail = FileReading.tail(
                  of: home.appendingPathComponent(path),
                  maxBytes: ClaudeTranscriptPromptReader.tailSize)
        else { return nil }
        return ClaudeTranscriptPromptReader.pendingQuestion(inTail: tail)
    }

    /// A session file can outlive a process that was killed.
    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
