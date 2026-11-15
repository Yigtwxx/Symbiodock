import Darwin
import Foundation
import SymbiodockCore

/// Claude Code keeps one small JSON file per running session in `~/.claude/sessions`,
/// with its name, folder and whether it is busy, idle or waiting for the user. Beside each
/// session's transcript, a `subagents` folder holds a small meta file per subagent.
/// While a session is busy, the end of its transcript tells whether it is compacting.
actor ClaudeCodeProvider: AgentSessionProvider {
    nonisolated let tool = AgentTool.claudeCode
    /// `~/.claude`
    private let home: URL

    /// What was read from a waiting session's transcript, until the file changes.
    private struct Asked {
        let stamp: FileStamp
        let question: String?
    }

    /// What was read from a subagent's meta file, until the file changes.
    private struct MetaEntry {
        let stamp: FileStamp
        let meta: ClaudeSubagentMeta?
    }

    /// The subagents a parent's transcript showed as ended, as of the transcript's stamp.
    private struct Ends {
        let stamp: FileStamp
        let ended: Set<String>
    }

    /// What a busy session's transcript showed about a compaction, as of the transcript's
    /// stamp. The mark is kept, not the verdict: the transcript does not change while a
    /// compaction runs, and the verdict depends on the clock.
    private struct Compaction {
        let stamp: FileStamp
        let mark: CompactionMark?
    }

    /// What one scan read or kept; whatever belongs to sessions that are gone is dropped.
    private struct Kept {
        var asked: [String: Asked] = [:]
        var metas: [String: MetaEntry] = [:]
        var ends: [String: Ends] = [:]
        var compactions: [String: Compaction] = [:]
    }

    private var asked: [String: Asked] = [:]
    private var metas: [String: MetaEntry] = [:]
    private var ends: [String: Ends] = [:]
    private var compactions: [String: Compaction] = [:]

    init(home: URL) {
        self.home = home
    }

    func sessions(in context: AgentScanContext) async -> [AgentSession] {
        let directory = home.appendingPathComponent("sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        else {
            asked.removeAll()
            metas.removeAll()
            ends.removeAll()
            compactions.removeAll()
            return []
        }

        var kept = Kept()
        defer {
            asked = kept.asked
            metas = kept.metas
            ends = kept.ends
            compactions = kept.compactions
        }
        return files.compactMap { url in
            guard url.pathExtension == "json",
                  let stamp = FileReading.stamp(of: url),
                  let data = FileReading.whole(url, maxBytes: ClaudeSessionParser.maximumFileSize),
                  let record = ClaudeSessionParser.record(from: data),
                  Self.isLive(record.pid, modified: stamp.modified, among: context.processes),
                  var session = ClaudeSessionParser.session(
                      from: record,
                      prompt: record.status == "waiting"
                          ? question(of: record, remembering: &kept.asked) : nil,
                      compacting: record.status == "busy"
                          && isCompacting(record, now: context.now, remembering: &kept.compactions),
                      fallbackSince: stamp.modified)
            else { return nil }
            session.subagents = subagents(of: record, now: context.now, remembering: &kept)
            return session
        }
    }

    /// The session's subagents still worth showing. A meta file is parsed again only when
    /// it changed. The parent's transcript is searched only while a subagent has not
    /// finished, and again only when the transcript changed.
    private func subagents(
        of record: ClaudeSessionRecord, now: Date, remembering kept: inout Kept
    ) -> [AgentSubagent] {
        guard let cwd = record.cwd, let sessionID = record.sessionID,
              let folderPath = ClaudeSubagentParser.folderRelativePath(cwd: cwd, sessionID: sessionID),
              let transcriptPath = ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
        else { return [] }
        let folder = home.appendingPathComponent(folderPath, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }

        var found: [(id: String, meta: ClaudeSubagentMeta, stamp: FileStamp)] = []
        for name in names {
            guard let id = ClaudeSubagentParser.agentID(metaFileName: name) else { continue }
            let url = folder.appendingPathComponent(name)
            guard let stamp = FileReading.stamp(of: url) else { continue }
            let entry = metas[url.path].flatMap { $0.stamp == stamp ? $0 : nil }
                ?? MetaEntry(
                    stamp: stamp,
                    meta: FileReading.whole(url, maxBytes: ClaudeSubagentParser.maximumMetaSize)
                        .flatMap(ClaudeSubagentParser.meta(from:)))
            kept.metas[url.path] = entry
            guard let meta = entry.meta else { continue }
            found.append((id, meta, stamp))
        }

        let open = found.filter { !$0.meta.isFinished }.map { (id: $0.id, meta: $0.meta) }
        let ended = open.isEmpty
            ? []
            : endedIDs(
                among: open, transcript: home.appendingPathComponent(transcriptPath),
                remembering: &kept.ends)

        return found.compactMap { item in
            // A finished subagent's times come from its meta file alone.
            let written = item.meta.isFinished
                ? nil : FileReading.stamp(of: folder.appendingPathComponent("agent-\(item.id).jsonl"))
            return ClaudeSubagentParser.subagent(
                id: item.id, meta: item.meta,
                started: written?.created ?? item.stamp.created,
                lastWrite: written?.modified ?? item.stamp.modified,
                metaModified: item.stamp.modified,
                hasEnded: ended.contains(item.id), now: now)
        }
    }

    /// Which open subagents the parent's transcript shows as ended. Once seen ended, a
    /// subagent stays ended though the sign scrolls out of the transcript's tail.
    private func endedIDs(
        among open: [(id: String, meta: ClaudeSubagentMeta)], transcript url: URL,
        remembering kept: inout [String: Ends]
    ) -> Set<String> {
        let openIDs = Set(open.map(\.id))
        let known = ends[url.path]
        guard let stamp = FileReading.stamp(of: url) else {
            return (known?.ended ?? []).intersection(openIDs)
        }
        if let known, known.stamp == stamp {
            kept[url.path] = known
            return known.ended.intersection(openIDs)
        }
        let seen = FileReading.tail(of: url, maxBytes: ClaudeTranscriptPromptReader.tailSize)
            .map { ClaudeSubagentParser.endedIDs(open, inTail: $0) } ?? []
        let ended = (known?.ended ?? []).intersection(openIDs).union(seen)
        kept[url.path] = Ends(stamp: stamp, ended: ended)
        return ended
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

    /// Whether a busy session is compacting its conversation, read from its transcript's
    /// end (see `ClaudeCompactionReader`). The transcript is read again only when its size
    /// or modification time changed.
    private func isCompacting(
        _ record: ClaudeSessionRecord, now: Date, remembering kept: inout [String: Compaction]
    ) -> Bool {
        guard let cwd = record.cwd, let sessionID = record.sessionID,
              let path = ClaudeSessionParser.transcriptRelativePath(cwd: cwd, sessionID: sessionID)
        else { return false }
        let url = home.appendingPathComponent(path)
        guard let stamp = FileReading.stamp(of: url) else { return false }
        let mark: CompactionMark?
        if let known = compactions[path], known.stamp == stamp {
            mark = known.mark
        } else {
            // A failed read is not remembered, so that it is tried again at the next scan.
            guard let tail = FileReading.tail(of: url, maxBytes: ClaudeCompactionReader.tailSize)
            else { return false }
            mark = ClaudeCompactionReader.compactionMark(inTail: tail)
        }
        kept[path] = Compaction(stamp: stamp, mark: mark)
        return mark.map { ClaudeCompactionReader.isCompacting($0, now: now) } ?? false
    }

    /// A session file can outlive its process, and its pid can then belong to anything.
    /// The process list the scan already has decides (see `ClaudeSessionParser.isLive`).
    /// Only when that list is empty, because the scan failed, is the pid probed, so that
    /// a failed scan does not make every session vanish. `EPERM` does not count: that pid
    /// belongs to another user.
    private nonisolated static func isLive(
        _ pid: Int32, modified: Date, among processes: [ProcessSnapshot]
    ) -> Bool {
        if processes.isEmpty { return kill(pid, 0) == 0 }
        return ClaudeSessionParser.isLive(pid: pid, fileModified: modified, among: processes)
    }
}
