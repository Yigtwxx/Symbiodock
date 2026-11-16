import Foundation

/// How one file of a batch comes out from under its cover.
public enum RevealStep: Equatable, Sendable {
    /// The tile opens on this result.
    case reveal(UUID, ConversionResult)
    /// The file leaves the shelf as the cover opens: an archive's files after the first.
    case leave(UUID)
}

/// One press of a chip over the selected files: which tiles it covers, which of them open
/// together, and what it says when it is over. The app runs the work and the clock; this only
/// decides, so the flow is tested without either. Spec: "Çoklu seçim ve toplu çevirme".
public struct ConversionBatch: Equatable, Sendable {
    public let label: String
    /// The files whose tiles it covers, in shelf order.
    public let files: [UUID]
    /// What each covered file becomes; empty for an archive.
    public let targets: [UUID: ConversionTarget]
    /// Several files and ZIP: one `Archive.zip` of every listed file.
    public let isArchive: Bool
    /// The files asked for that were held and not converting, in shelf order.
    private let listed: [UUID]
    /// Names of the listed files that can't become `label`.
    private let unsupported: [String]
    /// Covered files that lay in one stack when the batch began open together: the stack is
    /// one cocoon. An archive is one piece of work, so all its files open at once.
    private let groups: [[UUID]]
    private var results: [UUID: ConversionResult] = [:]

    /// `busy`: files already converting, which another batch holds.
    public init(label: String, ids: [UUID], shelf: FileShelf, busy: Set<UUID>) {
        let asked = Set(ids)
        let items = shelf.items.filter { asked.contains($0.id) && !busy.contains($0.id) }
        let plan = ConversionCatalog.plan(label: label, items: items)
        let covered = plan.archive ? items : items.filter { plan.targets[$0.id] != nil }
        let refused = Set(plan.unsupported)
        self.label = label
        files = covered.map(\.id)
        targets = plan.targets
        isArchive = plan.archive
        listed = items.map(\.id)
        unsupported = items.filter { refused.contains($0.id) }.map(\.name)
        if plan.archive {
            groups = files.isEmpty ? [] : [files]
        } else {
            // A stack's files are contiguous on the shelf, so a stack is one run here.
            var groups: [[UUID]] = []
            var stack: UUID?
            for item in covered {
                if item.stack == stack {
                    groups[groups.count - 1].append(item.id)
                } else {
                    groups.append([item.id])
                    stack = item.stack
                }
            }
            self.groups = groups
        }
    }

    /// Nothing to cover; at most something to say.
    public var isEmpty: Bool { files.isEmpty }

    /// Every covered file has its result, so every group has been handed out to open.
    public var isDecided: Bool { files.allSatisfy { results[$0] != nil } }

    public func holds(any ids: [UUID]) -> Bool { ids.contains(where: files.contains) }

    /// The work on one file ended. Returns the groups this completes, each ready to open. A
    /// file keeps its first result.
    public mutating func record(_ id: UUID, _ result: ConversionResult) -> [[RevealStep]] {
        guard !isArchive, files.contains(id), results[id] == nil else { return [] }
        results[id] = result
        return completed(by: [id])
    }

    /// The archive ended. Only the first tile carries the outcome: it becomes the archive while
    /// the others leave the shelf, or it says why not while the others open unchanged.
    public mutating func recordArchive(_ result: ConversionResult) -> [[RevealStep]] {
        guard isArchive, let first = files.first, results.isEmpty else { return [] }
        for id in files { results[id] = id == first ? result : .cancelled }
        return completed(by: files)
    }

    /// The person cancelled: every file still waiting opens unchanged. A file already
    /// converted keeps its result, since its new file is already on disk.
    public mutating func cancelRemaining() -> [[RevealStep]] {
        let waiting = files.filter { results[$0] == nil }
        for id in waiting { results[id] = .cancelled }
        return completed(by: waiting)
    }

    /// What it says once its tiles have opened, hung on the first listed file still `held`. A
    /// file converted alone says its own failure as it opens, and an archive's failure is said
    /// by its first tile; a batch says what it skipped and how many failed.
    public func notice(held: Set<UUID>) -> ShelfNotice? {
        guard !isArchive, let id = listed.first(where: held.contains) else { return nil }
        let alone = files.count + unsupported.count == 1
        let failed = alone ? 0 : results.values.filter { if case .failed = $0 { true } else { false } }.count
        guard let text = ShelfNotice.batchText(label: label, unsupported: unsupported, failed: failed)
        else { return nil }
        return ShelfNotice(id: id, text: text)
    }

    /// The groups touched by `ids` that now have every result.
    private func completed(by ids: [UUID]) -> [[RevealStep]] {
        let touched = Set(ids)
        return groups
            .filter { $0.contains(where: touched.contains) && $0.allSatisfy { results[$0] != nil } }
            .map(steps)
    }

    private func steps(_ group: [UUID]) -> [RevealStep] {
        if isArchive, let first = group.first, let result = results[first], case .converted = result {
            return [.reveal(first, result)] + group.dropFirst().map { .leave($0) }
        }
        return group.map { .reveal($0, results[$0] ?? .cancelled) }
    }
}

extension ConversionBatch {
    /// How long a file's work waits before it starts: the PDF printer holds the main actor, so
    /// it starts only once the cover has closed and the freeze cannot be seen.
    public static func startDelay(for engine: ConversionEngine, elapsed: TimeInterval) -> TimeInterval {
        engine == .printPDF ? max(0, EngulfTiming.engulf - elapsed) : 0
    }

    /// What a demo conversion pretends to make: the same path with the target's extension, a
    /// folder for Unzip. Nothing is written.
    public static func pretendResult(of item: ShelfItem, target: ConversionTarget) -> ConversionResult {
        let stem = item.url.deletingPathExtension()
        guard !target.pathExtension.isEmpty else { return .converted(url: stem, isDirectory: true) }
        return .converted(url: stem.appendingPathExtension(target.pathExtension), isDirectory: false)
    }

    /// What a demo archive pretends to make: `Archive.zip` beside the first file.
    public static func pretendArchive(beside item: ShelfItem) -> ConversionResult {
        .converted(
            url: item.url.deletingLastPathComponent().appendingPathComponent("Archive.zip"),
            isDirectory: false)
    }

    /// The column while its files convert: "Converting to PDF…", "Converting 3 files to PDF…".
    public static func progressText(label: String, files: Int) -> String {
        files == 1 ? "Converting to \(label)…" : "Converting \(files) files to \(label)…"
    }
}
