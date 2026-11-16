import Foundation

/// A file or folder the shelf holds.
public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var isDirectory: Bool
    /// The stack it lies in; a lone tile is the stack named after itself.
    public var stack: UUID

    public init(id: UUID = UUID(), url: URL, isDirectory: Bool, stack: UUID? = nil) {
        self.id = id
        self.url = url
        self.isDirectory = isDirectory
        self.stack = stack ?? id
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

/// Files put in the same place: a drawer whose front file is shown whole.
public struct ShelfStack: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Front first, never empty.
    public var items: [ShelfItem]

    public var front: ShelfItem { items[0] }
}

/// The files the island holds, grouped in stacks, newest first, with the ones picked.
public struct FileShelf: Equatable, Sendable {
    /// Stacks newest first; a stack's files are contiguous, front first.
    public private(set) var items: [ShelfItem]
    public private(set) var selection: Set<UUID>
    /// The file picked last. Always in `selection`; nil only when the selection is empty.
    public private(set) var selectedID: UUID?

    /// Items in the order given; a later item with a path already held is dropped, and the
    /// files of one stack are gathered where its first file is. Selects the first file.
    public init(items: [ShelfItem] = []) {
        var seen = Set<String>()
        let unique = items.filter { seen.insert(Self.key($0)).inserted }
        var order: [UUID] = []
        var grouped: [UUID: [ShelfItem]] = [:]
        for item in unique {
            if grouped[item.stack] == nil { order.append(item.stack) }
            grouped[item.stack, default: []].append(item)
        }
        self.items = order.flatMap { grouped[$0] ?? [] }
        selection = Set(self.items.prefix(1).map(\.id))
        selectedID = self.items.first?.id
    }

    public var isEmpty: Bool { items.isEmpty }
    /// Files, not stacks.
    public var count: Int { items.count }

    public var stacks: [ShelfStack] {
        var result: [ShelfStack] = []
        for item in items {
            if let last = result.last, last.id == item.stack {
                result[result.count - 1].items.append(item)
            } else {
                result.append(ShelfStack(id: item.stack, items: [item]))
            }
        }
        return result
    }

    /// The selected files in shelf order.
    public var selectedItems: [ShelfItem] { items.filter { selection.contains($0.id) } }

    public func stack(holding id: UUID) -> ShelfStack? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return stack(item.stack)
    }

    public func stack(_ id: UUID) -> ShelfStack? {
        let members = items.filter { $0.stack == id }
        return members.isEmpty ? nil : ShelfStack(id: id, items: members)
    }

    private static func key(_ item: ShelfItem) -> String { item.url.standardizedFileURL.path }

    // MARK: Putting files in stacks

    /// Dropped files. Several at once form one new stack (`newStack`); with `onto`, they join
    /// that stack in front. A file already held (same standardized path) moves: it keeps its
    /// id and leaves its old stack. Selects them.
    public mutating func add(_ new: [ShelfItem], onto stack: UUID? = nil, newStack: UUID = UUID()) {
        var seen = Set<String>()
        var arriving: [ShelfItem] = []
        for item in new where seen.insert(Self.key(item)).inserted {
            arriving.append(items.first { Self.key($0) == Self.key(item) } ?? item)
        }
        place(arriving, onto: stack, newStack: newStack)
    }

    /// A tile dropped on a tile: the files go in front of that stack and are selected.
    public mutating func move(_ ids: [UUID], onto stack: UUID) {
        guard self.stack(stack) != nil else { return }
        place(held(ids), onto: stack, newStack: UUID())
    }

    /// Each file becomes a lone tile right after the stack it left. A stack's only file stays.
    /// `newStacks` names the new stacks in the order of `ids`; without a name a file is the
    /// stack named after itself, unless another stack already holds that id.
    public mutating func separate(_ ids: [UUID], newStacks: [UUID]? = nil) {
        var stacks = self.stacks
        var lastAfter: [UUID: UUID] = [:]  // origin stack → the lone stack put after it last
        var done = Set<UUID>()
        for (position, id) in ids.enumerated() where done.insert(id).inserted {
            guard let origin = stacks.firstIndex(where: { $0.items.contains { $0.id == id } }),
                stacks[origin].items.count > 1
            else { continue }
            var item = stacks[origin].items.remove(at: stacks[origin].items.firstIndex { $0.id == id }!)
            let named = newStacks.flatMap { position < $0.count ? $0[position] : nil }
            let lone = named ?? Self.freshStackID(for: item.id, among: stacks)
            item.stack = lone
            let anchor = lastAfter[stacks[origin].id] ?? stacks[origin].id
            let at = stacks.firstIndex { $0.id == anchor }! + 1
            stacks.insert(ShelfStack(id: lone, items: [item]), at: at)
            lastAfter[stacks[origin].id] = lone
        }
        set(stacks)
    }

    /// Within its stack.
    public mutating func bringToFront(_ id: UUID) {
        var stacks = self.stacks
        guard let s = stacks.firstIndex(where: { $0.items.contains { $0.id == id } }),
            let i = stacks[s].items.firstIndex(where: { $0.id == id }), i > 0
        else { return }
        stacks[s].items.insert(stacks[s].items.remove(at: i), at: 0)
        set(stacks)
    }

    // MARK: Selection

    /// Exactly these; unknown ids are dropped and nothing at all keeps the selection.
    public mutating func select(_ ids: [UUID]) {
        let valid = held(ids).map(\.id)
        guard !valid.isEmpty else { return }
        selection = Set(valid)
        selectedID = valid.last
    }

    /// All of them selected → deselect them (never down to none); otherwise add them.
    public mutating func toggle(_ ids: [UUID]) {
        let valid = held(ids).map(\.id)
        guard !valid.isEmpty else { return }
        if valid.allSatisfy(selection.contains) {
            let rest = selection.subtracting(valid)
            guard !rest.isEmpty else { return }
            selection = rest
            if selectedID.map(rest.contains) != true { selectedID = selectedItems.last?.id }
        } else {
            selection.formUnion(valid)
            selectedID = valid.last
        }
    }

    // MARK: Taking files away

    /// Unknown ids are ignored. When the whole selection goes, it falls to the file that takes
    /// the place of the first selected one removed, else the last.
    public mutating func remove(_ ids: [UUID]) {
        let gone = Set(ids)
        let slot = items.firstIndex { gone.contains($0.id) && selection.contains($0.id) }
        let shift = slot.map { items[..<$0].filter { gone.contains($0.id) }.count } ?? 0
        items.removeAll { gone.contains($0.id) }
        guard let slot else { return }
        selection.subtract(gone)
        if selection.isEmpty, !items.isEmpty {
            selection = [items[min(slot - shift, items.count - 1)].id]
        }
        if selectedID.map(selection.contains) != true { selectedID = selectedItems.last?.id }
    }

    /// The file became another (a conversion's result). If another item already holds the
    /// new path, that other item leaves the shelf.
    public mutating func replace(_ id: UUID, url: URL, isDirectory: Bool) {
        guard items.contains(where: { $0.id == id }) else { return }
        let key = url.standardizedFileURL.path
        let other = items.filter { $0.id != id && Self.key($0) == key }.map(\.id)
        if !other.isEmpty { remove(other) }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].url = url
        items[index].isDirectory = isDirectory
    }

    public mutating func clear() {
        items = []
        selection = []
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

    // MARK: Helpers

    /// The held items for these ids, in the order given, each once.
    private func held(_ ids: [UUID]) -> [ShelfItem] {
        var seen = Set<UUID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return items.first { $0.id == id }
        }
    }

    /// A lone file is the stack named after it, unless another stack already holds that id.
    private static func freshStackID(for id: UUID, among stacks: [ShelfStack]) -> UUID {
        stacks.contains { $0.id == id } ? UUID() : id
    }

    /// Takes the files out of wherever they lie and puts them in front of the target stack
    /// (which keeps its place, even when they were all it held), or else in a new stack in
    /// front of the shelf. Selects them.
    private mutating func place(_ arriving: [ShelfItem], onto target: UUID?, newStack: UUID) {
        guard !arriving.isEmpty else { return }
        let moving = Set(arriving.map(\.id))
        let known = target.flatMap { stack($0) == nil ? nil : $0 }
        var stacks: [ShelfStack] = []
        var slot = 0
        for s in self.stacks {
            let kept = s.items.filter { !moving.contains($0.id) }
            if s.id == known { slot = stacks.count }
            if !kept.isEmpty { stacks.append(ShelfStack(id: s.id, items: kept)) }
        }
        if let known {
            if slot < stacks.count, stacks[slot].id == known {
                stacks[slot].items.insert(contentsOf: arriving, at: 0)
            } else {
                stacks.insert(ShelfStack(id: known, items: arriving), at: slot)
            }
        } else {
            let id =
                arriving.count > 1
                ? (stacks.contains { $0.id == newStack } ? UUID() : newStack)
                : Self.freshStackID(for: arriving[0].id, among: stacks)
            stacks.insert(ShelfStack(id: id, items: arriving), at: 0)
        }
        set(stacks)
        selection = moving
        selectedID = arriving.last?.id
    }

    /// Flattens the stacks back into `items`, every file naming the stack it lies in.
    private mutating func set(_ stacks: [ShelfStack]) {
        items = stacks.flatMap { stack in
            stack.items.map { item -> ShelfItem in
                var item = item
                item.stack = stack.id
                return item
            }
        }
    }
}
