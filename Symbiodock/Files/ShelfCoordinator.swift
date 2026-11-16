import AppKit
import SymbiodockCore
import os

/// Keeps the shelf: puts files on it, takes them off, converts them, remembers them between
/// launches and feeds their previews. The island's state holds the shelf; this is what changes it.
@MainActor
final class ShelfCoordinator {
    /// Counts only (never names or paths). Watch with:
    /// `log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "shelf"'`
    private static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "shelf")

    private let state: IslandState
    private let previews: FilePreviews
    private let storage: ShelfStorage
    private let converter: FileConverter

    /// A demo shelf holds files that are not there: it is never saved and never cleaned, and its
    /// conversions only pretend.
    var isDemo = false
    /// False for a shelf that must leave the saved one alone (the headless flow hook): it
    /// converts for real but is never saved and never cleaned.
    var persists = true

    /// One press of a chip: its files convert one after another in `work`.
    private struct Batch {
        var plan: ConversionBatch
        /// When its covers began to close, all at once.
        let started: Date
        var work: Task<Void, Never>?
        /// Groups handed out to open, waiting for the cover's minimum time, by follow-up.
        var pending: [UUID: [RevealStep]] = [:]
    }

    private var batches: [UUID: Batch] = [:]
    /// The tick as covers close and every reveal. They finish what a batch began, so a cancel
    /// leaves them running; `stop` does not.
    private var followUps: [UUID: Task<Void, Never>] = [:]

    /// How long a demo file pretends to convert.
    private static let pretendWork: Duration = .seconds(1.2)

    init(
        state: IslandState, previews: FilePreviews, converter: FileConverter,
        storage: ShelfStorage = .shared
    ) {
        self.state = state
        self.previews = previews
        self.converter = converter
        self.storage = storage
    }

    /// Brings back the saved shelf, clears what earlier runs left in the storage, loads previews.
    func start() {
        let items = ShelfStore.load()
        state.restoreShelf(items)
        storage.purgeOrphans(keeping: items.map(\.url))
        previews.refresh(state.shelf.items)
        Self.log.notice("restored \(items.count) items")
    }

    /// Puts files and folders on the shelf: onto a stack they join it in front; into a new
    /// stack the files of one drop gather in the order they arrive, so a drop is one drawer
    /// even when its files come one by one. One already there moves (to that stack).
    func add(_ urls: [URL], onto place: ShelfDropPlace = .newStack(UUID())) {
        let items = urls.map { url -> ShelfItem in
            let file = url.standardizedFileURL
            let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return ShelfItem(url: file, isDirectory: isDirectory)
        }
        guard !items.isEmpty else { return }
        switch place {
        case .onto(let stack): state.addShelfItems(items, onto: stack)
        case .newStack(let stack): state.addShelfItems(items, into: stack)
        }
        changed()
    }

    /// Files dragged within the island: onto a stack they join it in front; let go on the
    /// row's empty part, each becomes a tile of its own. Nothing leaves the shelf.
    func move(_ ids: [UUID], onto stack: UUID?) {
        if let stack {
            state.moveShelfItems(ids, onto: stack)
        } else {
            state.separateShelfItems(ids)
        }
        save()
    }

    func handle(_ request: FileRequest) {
        switch request {
        case .reveal(let ids):
            let urls = items(ids).map(\.url)
            guard !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .remove(let ids):
            let removed = items(ids)
            guard !removed.isEmpty else { return }
            cancelBatches(holding: removed.map(\.id))
            state.removeShelfItems(removed.map(\.id))
            changed()
            removed.map(\.url).forEach(discard)
        case .unstack(let stack):
            guard let held = state.shelf.stack(stack) else { return }
            FileDropReader.log.notice(
                "stack \(String(stack.uuidString.prefix(8)), privacy: .public) unstacked from the column; files: \(held.items.count)")
            state.separateShelfItems(held.items.map(\.id))
            changed()
        case .convert(let ids, let label):
            convert(ids, label: label)
        case .cancel(let ids):
            cancelBatches(holding: ids)
        }
    }

    /// A click on a stack. A file alone (a tab, or the front card's top strip) is picked and
    /// comes to the front of its drawer; the body picks the whole drawer. With ⌘ the files join
    /// the selection, or leave it if they were all in it, and nothing moves.
    func pick(_ stackID: UUID, _ hit: StackLayout.Hit, command: Bool) {
        guard let stack = state.shelf.stack(stackID) else { return }
        switch hit {
        case .file(let index):
            guard stack.items.indices.contains(index) else { return }
            let id = stack.items[index].id
            if command {
                state.toggleShelfItems([id])
            } else {
                state.selectShelfItems([id])
                guard index > 0 else { return }
                state.bringShelfItemToFront(id)
                save()
            }
        case .body:
            let ids = stack.items.map(\.id)
            if command { state.toggleShelfItems(ids) } else { state.selectShelfItems(ids) }
        }
    }

    /// Files taken by the app they were dragged to: they are off the shelf, the files on disk
    /// are not touched.
    func removeAfterDragOut(_ ids: [UUID]) {
        cancelBatches(holding: ids)
        state.removeShelfItems(ids)
        changed()
    }

    func clear() {
        cancelBatches(holding: state.shelf.items.map(\.id))
        let urls = state.shelf.items.map(\.url)
        state.clearShelf()
        changed()
        urls.forEach(discard)
    }

    /// Quitting: the work stops and its tools are terminated before this returns. A file
    /// already converted keeps its result in the saved shelf, even while the rest of its stack
    /// was still converting; no tile is left covered.
    func stop() {
        let running = Array(batches.values)
        batches = [:]
        running.forEach { $0.work?.cancel() }
        followUps.values.forEach { $0.cancel() }
        followUps = [:]
        for batch in running { _ = open(batch.plan.decidedSteps) }
        for id in state.conversions.keys { state.endConversion(id) }
        converter.runner.helpers.terminateAll()
        save()
    }

    // MARK: Converting

    /// Every tile of the batch closes at the same instant; the files then convert one after
    /// another in shelf order. A file another batch is converting is left to it.
    private func convert(_ ids: [UUID], label: String) {
        let plan = ConversionBatch(
            label: label, ids: ids, shelf: state.shelf, busy: Set(state.conversions.keys))
        guard !plan.isEmpty else {
            // Nothing to cover: only what could not be done, said at once.
            if let notice = plan.notice(held: Set(state.shelf.items.map(\.id))) {
                state.setShelfNotice(notice)
            }
            return
        }
        let started = Date()
        for id in plan.files { state.beginConversion(id, label: label, at: started) }
        let batchID = UUID()
        batches[batchID] = Batch(plan: plan, started: started)
        Self.log.notice("converting \(plan.files.count) files")
        follow { coordinator in
            await Self.pause(EngulfTiming.engulf)
            guard !Task.isCancelled, coordinator.isCovering(batchID) else { return }
            Haptics.tick()
        }
        batches[batchID]?.work = Task { [weak self] in await self?.run(batchID) }
    }

    /// The batch's work. A cancel stops it between files or inside the tool; the file being
    /// converted reports how it ended, and every file still waiting opens unchanged.
    private func run(_ batchID: UUID) async {
        guard let batch = batches[batchID] else { return }
        let plan = batch.plan
        if plan.isArchive {
            let result = await archive(plan.files)
            decide(batchID) { $0.recordArchive(result) }
        } else {
            for id in plan.files {
                guard !Task.isCancelled else { break }
                guard let target = plan.targets[id] else { continue }
                let result = await convertOne(id, to: target, started: batch.started)
                decide(batchID) { $0.record(id, result) }
            }
        }
        if Task.isCancelled { decide(batchID) { $0.cancelRemaining() } }
    }

    private func convertOne(_ id: UUID, to target: ConversionTarget, started: Date) async
        -> ConversionResult
    {
        // Gone from the shelf (its cover went with it): nothing to convert or to show.
        guard state.conversions[id] != nil, let item = items([id]).first else { return .cancelled }
        do {
            if isDemo {
                try await Task.sleep(for: Self.pretendWork)
                return ConversionBatch.pretendResult(of: item, target: target)
            }
            let wait = ConversionBatch.startDelay(
                for: target.engine, elapsed: Date().timeIntervalSince(started))
            if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
            let made = try await converter.convert(item.url, isDirectory: item.isDirectory, to: target)
            return .converted(url: made.url, isDirectory: made.isDirectory)
        } catch let failure as ConversionFailure {
            return .failed(failure.message)
        } catch {
            return .cancelled
        }
    }

    private func archive(_ ids: [UUID]) async -> ConversionResult {
        let sources = items(ids)
        guard sources.count == ids.count, let first = sources.first else { return .cancelled }
        do {
            if isDemo {
                try await Task.sleep(for: Self.pretendWork)
                return ConversionBatch.pretendArchive(beside: first)
            }
            return .converted(url: try await converter.archive(sources.map(\.url)), isDirectory: false)
        } catch let failure as ConversionFailure {
            return .failed(failure.message)
        } catch {
            return .cancelled
        }
    }

    /// Records an outcome and sends every group it completes to open.
    private func decide(_ batchID: UUID, _ change: (inout ConversionBatch) -> [[RevealStep]]) {
        guard var batch = batches[batchID] else { return }
        let groups = change(&batch.plan)
        batches[batchID] = batch
        groups.forEach { scheduleReveal($0, of: batchID) }
    }

    /// The group opens once its cover has closed and held, then is an ordinary tile again.
    private func scheduleReveal(_ group: [RevealStep], of batchID: UUID) {
        guard let started = batches[batchID]?.started else { return }
        let token = UUID()
        batches[batchID]?.pending[token] = group
        follow(token) { coordinator in
            await Self.pause(EngulfTiming.revealDelay(elapsed: Date().timeIntervalSince(started)))
            guard !Task.isCancelled else { return }
            let opened = coordinator.reveal(token, of: batchID)
            await Self.pause(
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? EngulfTiming.stillFade : EngulfTiming.reveal)
            // Stopped: `stop` ended every conversion itself.
            guard !Task.isCancelled else { return }
            for id in opened { coordinator.state.endConversion(id) }
        }
    }

    /// Opens a pending group and returns the files it revealed. The last group of a batch says
    /// what the batch could not do: after the tiles' own failures, so a batch's summary is the
    /// notice left.
    private func reveal(_ token: UUID, of batchID: UUID) -> [UUID] {
        guard var batch = batches[batchID], let group = batch.pending.removeValue(forKey: token)
        else { return [] }
        batches[batchID] = batch
        let before = state.shelf
        let opened = open(group)
        if !opened.isEmpty { Haptics.tick() }
        // Tiles that open unchanged (cancelled, failed) leave nothing to save or to preview.
        if state.shelf != before { changed() }
        if batch.plan.isDecided, batch.pending.isEmpty {
            batches[batchID] = nil
            if let notice = batch.plan.notice(held: Set(state.shelf.items.map(\.id))) {
                state.setShelfNotice(notice)
            }
        }
        return opened
    }

    /// The tiles change under their closed covers; returns the files revealed. Only files still
    /// covered take part (see `ConversionBatch.settle`). An archive's other files leave the
    /// shelf; they stay on disk, and a copy in the shelf's storage goes at the next launch, like
    /// a file dragged out.
    private func open(_ group: [RevealStep]) -> [UUID] {
        let now = Date()
        var opened: [UUID] = []
        var leaving: [UUID] = []
        for step in ConversionBatch.settle(group, covered: Set(state.conversions.keys)) {
            switch step {
            case .reveal(let id, let result):
                state.revealConversion(id, result: result, at: now)
                opened.append(id)
            case .leave(let id):
                leaving.append(id)
            }
        }
        if !leaving.isEmpty { state.removeShelfItems(leaving) }
        return opened
    }

    /// A batch whose covers have not all started to open.
    private func isCovering(_ batchID: UUID) -> Bool {
        guard let files = batches[batchID]?.plan.files else { return false }
        return files.contains { id in
            state.conversions[id].map { $0.revealStarted == nil } ?? false
        }
    }

    /// The batches in which any of these files still waits stop; what they already converted
    /// is kept. A file already decided stops nothing: dragging out a converted tile must not
    /// cancel the files still converting after it.
    private func cancelBatches(holding ids: [UUID]) {
        for batch in batches.values where batch.plan.holds(any: ids) { batch.work?.cancel() }
    }

    /// Waits on the effect's clock, tightly enough that a tick or a reveal lands with the
    /// cover's frames (the default leeway let a reveal slip ~60 ms). Returns early when cancelled.
    private static func pause(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(5))
    }

    /// Runs `body` as a follow-up that `stop` can cancel.
    private func follow(
        _ token: UUID = UUID(), _ body: @escaping @MainActor (ShelfCoordinator) async -> Void
    ) {
        followUps[token] = Task { [weak self] in
            guard let self else { return }
            await body(self)
            self.followUps[token] = nil
        }
    }

    // MARK: Helpers

    private func items(_ ids: [UUID]) -> [ShelfItem] {
        state.shelf.items.filter { ids.contains($0.id) }
    }

    /// A file the shelf made for itself goes with its tile; one the person owns never does.
    private func discard(_ url: URL) {
        guard persists, !isDemo else { return }
        storage.discard(url)
    }

    private func changed() {
        save()
        previews.refresh(state.shelf.items)
    }

    private func save() {
        guard persists, !isDemo else { return }
        ShelfStore.save(state.shelf.items)
    }
}

/// Where the files of one drop go. Promised files and images arrive one at a time, each
/// naming the same place, so that one drop stays one drawer.
enum ShelfDropPlace: Equatable, Sendable {
    /// The stack shown as the target when the drop was let go: they join it in front.
    case onto(UUID)
    /// A stack made for this drop: the first file to arrive makes it, the next join behind.
    case newStack(UUID)
}
