import Foundation
import SymbiodockCore

/// Codex writes every thread to a rollout file. The file's first line says which thread
/// it is and its last turn event says whether a turn is running. Only these files and the
/// index of thread names are read; Codex's databases are left alone.
actor CodexProvider: AgentSessionProvider {
    nonisolated let tool = AgentTool.codex
    /// `~/.codex`
    private let home: URL
    /// How many day folders back a thread can still be alive in.
    private static let dayFolders = 3

    private struct Entry {
        let stamp: FileStamp
        let meta: CodexThreadMeta?
        let state: CodexTurnState?
    }

    /// What was read from each rollout, until the file changes.
    private var cache: [String: Entry] = [:]
    private var titles: [String: String] = [:]
    private var titlesStamp: FileStamp?

    init(home: URL) {
        self.home = home
    }

    func sessions(in context: AgentScanContext) async -> [AgentSession] {
        let codex = context.processes.filter { AgentProcessMatcher.tool(for: $0) == .codex }
        // A thread is live only while Codex itself runs.
        guard !codex.isEmpty else {
            cache.removeAll()
            return []
        }

        var listed: [(meta: CodexThreadMeta, session: AgentSession)] = []
        var children: [(id: String, subagent: AgentSubagent)] = []
        var parents: [String: String] = [:]
        var live: [String: Entry] = [:]
        for url in recentRollouts() {
            guard let stamp = FileReading.stamp(of: url),
                  context.now.timeIntervalSince(stamp.modified) <= CodexRolloutParser.workingListing
            else { continue }
            let entry = entry(for: url, stamp: stamp)
            live[url.path] = entry
            guard let meta = entry.meta else { continue }
            if let parent = meta.parentID { parents[meta.id] = parent }
            guard let state = entry.state else { continue }
            if meta.isSubagent {
                if let subagent = CodexRolloutParser.subagent(
                    meta: meta, state: state, modified: stamp.modified, now: context.now)
                {
                    // Two rollouts may carry the same subagent; keep the first.
                    if !children.contains(where: { $0.id == meta.id }) {
                        children.append((meta.id, subagent))
                    }
                }
                continue
            }
            guard CodexRolloutParser.isListed(state, modified: stamp.modified, now: context.now)
            else { continue }
            listed.append((
                meta,
                CodexRolloutParser.session(
                    meta: meta, state: state, title: title(of: meta.id),
                    pid: Self.process(for: meta, among: codex))))
        }
        cache = live

        // Each subagent hangs under the listed thread it descends from.
        let listedIDs = Set(listed.map(\.meta.id))
        var branches: [String: [AgentSubagent]] = [:]
        for child in children {
            guard let root = CodexRolloutParser.rootID(of: child.id, parents: parents, listed: listedIDs)
            else { continue }
            branches[root, default: []].append(child.subagent)
        }
        return listed.map { item in
            var session = item.session
            session.subagents = branches[item.meta.id] ?? []
            return session
        }
    }

    /// Parses a rollout again only if it changed; the first line never changes.
    private func entry(for url: URL, stamp: FileStamp) -> Entry {
        let known = cache[url.path]
        if let known, known.stamp == stamp { return known }
        let meta = known?.meta
            ?? FileReading.head(of: url, maxBytes: CodexRolloutParser.headSize)
                .flatMap(CodexRolloutParser.meta(fromHead:))
        let state = FileReading.tail(of: url, maxBytes: CodexRolloutParser.tailSize)
            .flatMap(CodexRolloutParser.turnState(inTail:))
        return Entry(stamp: stamp, meta: meta, state: state)
    }

    /// The rollout files in the newest day folders, `sessions/YYYY/MM/DD/`.
    private func recentRollouts() -> [URL] {
        let root = home.appendingPathComponent("sessions", isDirectory: true)
        var days: [URL] = []
        for year in Self.folders(in: root) {
            for month in Self.folders(in: year) {
                for day in Self.folders(in: month) {
                    days.append(day)
                    if days.count == Self.dayFolders { break }
                }
                if days.count == Self.dayFolders { break }
            }
            if days.count == Self.dayFolders { break }
        }
        return days.flatMap { day in
            ((try? FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
        }
    }

    /// Sub-folders, newest name first. The names are zero-padded numbers.
    private static func folders(in url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func title(of id: String) -> String? {
        let url = home.appendingPathComponent("session_index.jsonl")
        if let stamp = FileReading.stamp(of: url), stamp != titlesStamp {
            titlesStamp = stamp
            titles = FileReading.tail(of: url, maxBytes: CodexRolloutParser.tailSize)
                .map(CodexSessionIndex.titles(from:)) ?? [:]
        }
        return titles[id]
    }

    /// The Codex process a thread belongs to: the only one running in the thread's folder,
    /// or, for a desktop thread, the desktop app's own Codex process.
    private static func process(
        for meta: CodexThreadMeta, among codex: [ProcessSnapshot]
    ) -> Int32? {
        let inFolder = codex.filter { $0.workingDirectory != nil && $0.workingDirectory == meta.cwd }
        if inFolder.count == 1 { return inFolder[0].pid }
        if meta.originator == "Codex Desktop" {
            return codex.first { $0.terminal == nil }?.pid
        }
        return nil
    }
}
