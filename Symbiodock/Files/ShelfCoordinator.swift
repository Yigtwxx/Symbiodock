import AppKit
import SymbiodockCore
import os

/// Keeps the shelf: puts files on it, takes them off, remembers them between launches and
/// feeds their previews. The island's state holds the shelf; this is what changes it.
@MainActor
final class ShelfCoordinator {
    /// Counts only (never names or paths). Watch with:
    /// `log stream --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "shelf"'`
    private static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "shelf")

    private let state: IslandState
    private let previews: FilePreviews
    private let storage: ShelfStorage

    /// A demo shelf holds files that are not there: it is never saved and never cleaned.
    var isDemo = false

    init(state: IslandState, previews: FilePreviews, storage: ShelfStorage = .shared) {
        self.state = state
        self.previews = previews
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

    /// Puts files and folders on the shelf; one already there moves to the front.
    func add(_ urls: [URL]) {
        let items = urls.map { url -> ShelfItem in
            let file = url.standardizedFileURL
            let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return ShelfItem(url: file, isDirectory: isDirectory)
        }
        guard !items.isEmpty else { return }
        state.addShelfItems(items)
        changed()
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
            state.removeShelfItems(removed.map(\.id))
            changed()
            removed.map(\.url).forEach(discard)
        case .unstack(let stack):
            guard let held = state.shelf.stack(stack) else { return }
            state.separateShelfItems(held.items.map(\.id))
            changed()
        case .convert, .cancel:
            // Conversions come with the converter.
            break
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

    /// The tile left with a drag that was accepted: it is off the shelf, the file is not touched.
    func removeAfterDragOut(_ id: UUID) {
        state.removeShelfItems([id])
        changed()
    }

    func clear() {
        let urls = state.shelf.items.map(\.url)
        state.clearShelf()
        changed()
        urls.forEach(discard)
    }

    func stop() {
        save()
    }

    private func items(_ ids: [UUID]) -> [ShelfItem] {
        state.shelf.items.filter { ids.contains($0.id) }
    }

    /// A file the shelf made for itself goes with its tile; one the person owns never does.
    private func discard(_ url: URL) {
        guard !isDemo else { return }
        storage.discard(url)
    }

    private func changed() {
        save()
        previews.refresh(state.shelf.items)
    }

    private func save() {
        guard !isDemo else { return }
        ShelfStore.save(state.shelf.items)
    }
}
