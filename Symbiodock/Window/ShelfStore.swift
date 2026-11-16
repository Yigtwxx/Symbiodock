import Foundation
import SymbiodockCore

/// Remembers the shelf between launches. A file is kept as a bookmark, not a path, so a
/// file that was moved or renamed in the meantime is still found.
enum ShelfStore {
    private static let key = "shelfItems"

    private struct Record: Codable {
        var id: UUID
        var bookmark: Data
        var isDirectory: Bool
        /// Absent in what older versions saved: the item is then its own stack.
        var stack: UUID?
    }

    /// The saved items, newest first. One that can no longer be reached is dropped.
    @MainActor
    static func load() -> [ShelfItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
            let records = try? PropertyListDecoder().decode([Record].self, from: data)
        else { return [] }
        return records.compactMap { record in
            var stale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: record.bookmark, options: [.withoutUI],
                    relativeTo: nil, bookmarkDataIsStale: &stale),
                (try? url.checkResourceIsReachable()) == true
            else { return nil }
            return ShelfItem(
                id: record.id, url: url, isDirectory: record.isDirectory, stack: record.stack)
        }
    }

    @MainActor
    static func save(_ items: [ShelfItem]) {
        // Bookmarks are made again each time, so a stale one never outlives a launch.
        let records = items.compactMap { item -> Record? in
            guard let bookmark = try? item.url.bookmarkData() else { return nil }
            return Record(
                id: item.id, bookmark: bookmark, isDirectory: item.isDirectory, stack: item.stack)
        }
        guard let data = try? PropertyListEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
