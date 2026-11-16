import Foundation

/// A file or folder the shelf holds.
public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var isDirectory: Bool

    public init(id: UUID = UUID(), url: URL, isDirectory: Bool) {
        self.id = id
        self.url = url
        self.isDirectory = isDirectory
    }

    public var name: String { url.lastPathComponent }

    public var kind: FileKind { FileKind.of(pathExtension: url.pathExtension, isDirectory: isDirectory) }

    /// The tile's label: the extension, shortened to fit; a stand-in when there is none.
    public var badge: String {
        let ext = url.pathExtension
        if ext.isEmpty { return isDirectory ? "FOLDER" : "FILE" }
        return String(ext.uppercased().prefix(5))
    }
}

/// The files the island holds, newest first, with the one the tile shows.
public struct FileShelf: Equatable, Sendable {
    public private(set) var items: [ShelfItem]
    public private(set) var selectedID: UUID?

    public init(items: [ShelfItem] = []) {
        self.items = items
        selectedID = items.first?.id
    }

    public var selected: ShelfItem? { items.first { $0.id == selectedID } }
    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    private static func key(_ item: ShelfItem) -> String { item.url.standardizedFileURL.path }

    /// Puts the items in front, in the order given, and selects the first of them. An item
    /// whose standardized path is already held moves to the front and keeps its id.
    public mutating func add(_ new: [ShelfItem]) {
        var front: [ShelfItem] = []
        var seen = Set<String>()
        for item in new {
            let key = Self.key(item)
            guard seen.insert(key).inserted else { continue }
            front.append(items.first { Self.key($0) == key } ?? item)
        }
        guard !front.isEmpty else { return }
        let frontIDs = Set(front.map(\.id))
        items = front + items.filter { !frontIDs.contains($0.id) }
        selectedID = front[0].id
    }

    /// Selection moves to the item that takes its place, else the last, else nil.
    public mutating func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        guard selectedID == id else { return }
        selectedID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
    }

    public mutating func replace(_ id: UUID, url: URL, isDirectory: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].url = url
        items[index].isDirectory = isDirectory
    }

    public mutating func select(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    public mutating func clear() {
        items = []
        selectedID = nil
    }

    /// Distinct kinds, newest first, at most three: the bubble's discs, front first.
    public var bubbleKinds: [FileKind] {
        var kinds: [FileKind] = []
        for item in items where !kinds.contains(item.kind) {
            kinds.append(item.kind)
            if kinds.count == 3 { break }
        }
        return kinds
    }
}
