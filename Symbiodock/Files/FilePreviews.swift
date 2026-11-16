import AppKit
import Observation
import QuickLookThumbnailing
import SymbiodockCore
import UniformTypeIdentifiers

/// What a tile shows of its file: a thumbnail once Quick Look has made one, the file's own
/// icon until then, and its size.
@MainActor
@Observable
final class FilePreviews {
    private struct Entry {
        var url: URL
        var image: NSImage
    }

    private var entries: [UUID: Entry] = [:]
    private var details: [UUID: String] = [:]
    /// The urls whose thumbnail and size are being loaded.
    @ObservationIgnored private var loading: [UUID: URL] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    /// The thumbnail once loaded, else the file's or type's icon.
    func image(for item: ShelfItem) -> NSImage? {
        entries[item.id]?.url == item.url ? entries[item.id]?.image : nil
    }

    /// "2.4 MB"; nil for folders and until loaded.
    func detail(for item: ShelfItem) -> String? {
        entries[item.id]?.url == item.url ? details[item.id] : nil
    }

    /// Loads what is missing and forgets what is gone.
    func refresh(_ items: [ShelfItem]) {
        let ids = Set(items.map(\.id))
        for id in entries.keys where !ids.contains(id) {
            entries[id] = nil
            details[id] = nil
        }
        for id in tasks.keys where !ids.contains(id) {
            tasks[id]?.cancel()
            tasks[id] = nil
            loading[id] = nil
        }
        for item in items where entries[item.id]?.url != item.url {
            guard loading[item.id] != item.url else { continue }
            load(item)
        }
    }

    private func load(_ item: ShelfItem) {
        let id = item.id
        let url = item.url
        loading[id] = url
        tasks[id]?.cancel()
        let isDirectory = item.isDirectory
        if entries[id]?.url != url {
            entries[id] = Entry(url: url, image: Self.icon(for: url, isDirectory: isDirectory))
            details[id] = nil
        }
        tasks[id] = Task { [weak self] in
            let size = isDirectory ? nil : await Self.fileSize(of: url)
            let thumbnail = await Self.thumbnail(of: url)
            guard !Task.isCancelled, let self, self.loading[id] == url else { return }
            self.loading[id] = nil
            self.tasks[id] = nil
            if let thumbnail { self.entries[id] = Entry(url: url, image: thumbnail) }
            if let size { self.details[id] = size }
        }
    }

    /// A file that is not there (the demo shelf) gets its type's icon; a folder has no extension
    /// to tell it by.
    private static func icon(for url: URL, isDirectory: Bool) -> NSImage {
        if FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let type = isDirectory ? .folder : UTType(filenameExtension: url.pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    /// Read off the main actor: a file on a network volume can take a while.
    private static func fileSize(of url: URL) async -> String? {
        await Task.detached {
            guard let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return nil as String?
            }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }.value
    }

    private static func thumbnail(of url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 48, height: 48),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
            for: request)
        return representation?.nsImage
    }
}
