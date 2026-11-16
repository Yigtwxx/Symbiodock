import AppKit
import Observation
import QuickLookThumbnailing
import SymbiodockCore

/// What a card shows of its file: the file's own picture once Quick Look has made one, and
/// its size. Never the file's icon: a card without a picture shows its kind's symbol.
@MainActor
@Observable
final class FilePreviews {
    private struct Entry {
        var url: URL
        var image: NSImage?
        var bytes: Int64?
    }

    /// Large enough to fill a card's top at twice the scale without blurring.
    private static let thumbnailSize = CGSize(width: 128, height: 128)

    private var entries: [UUID: Entry] = [:]
    /// The urls whose picture and size are being loaded.
    @ObservationIgnored private var loading: [UUID: URL] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    /// A photo, a video's frame or a document's page; nil for kinds without one and until made.
    func image(for item: ShelfItem) -> NSImage? {
        entry(item)?.image
    }

    /// The file's size in bytes; nil for folders and until read.
    func size(for item: ShelfItem) -> Int64? {
        entry(item)?.bytes
    }

    /// Loads what is missing and forgets what is gone.
    func refresh(_ items: [ShelfItem]) {
        let ids = Set(items.map(\.id))
        for id in entries.keys where !ids.contains(id) {
            entries[id] = nil
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

    #if DEBUG
    /// What a demo file looks like, since it is not on disk; `refresh` keeps it.
    func stage(_ item: ShelfItem, image: NSImage?, bytes: Int64?) {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        loading[item.id] = nil
        entries[item.id] = Entry(url: item.url, image: image, bytes: bytes)
    }
    #endif

    private func entry(_ item: ShelfItem) -> Entry? {
        guard let entry = entries[item.id], entry.url == item.url else { return nil }
        return entry
    }

    /// Only kinds whose look is their content get a picture; a sound or an archive has none
    /// worth showing at this size, and a folder's would be the icon.
    private static func hasPicture(_ kind: FileKind) -> Bool {
        switch kind {
        case .image, .video, .pdf, .document: true
        case .audio, .archive, .folder, .other: false
        }
    }

    private func load(_ item: ShelfItem) {
        let id = item.id
        let url = item.url
        let isDirectory = item.isDirectory
        let wantsPicture = Self.hasPicture(item.kind)
        loading[id] = url
        tasks[id]?.cancel()
        // Until its picture is made, a file that changed shows its kind's symbol.
        entries[id] = Entry(url: url)
        tasks[id] = Task { [weak self] in
            let bytes = isDirectory ? nil : await Self.fileSize(of: url)
            let image = wantsPicture ? await Self.thumbnail(of: url) : nil
            guard !Task.isCancelled, let self, self.loading[id] == url else { return }
            self.loading[id] = nil
            self.tasks[id] = nil
            if image != nil || bytes != nil {
                self.entries[id] = Entry(url: url, image: image, bytes: bytes)
            }
        }
    }

    /// Read off the main actor: a file on a network volume can take a while.
    private static func fileSize(of url: URL) async -> Int64? {
        await Task.detached {
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        }.value
    }

    private static func thumbnail(of url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: thumbnailSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(
            for: request)
        return representation?.nsImage
    }
}
