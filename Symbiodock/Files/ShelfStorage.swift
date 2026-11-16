import Foundation

/// The folder the shelf keeps what it was handed as a promise or as raw data, one folder
/// per piece so that removing a tile removes exactly its file. Files the person dropped
/// from elsewhere stay where they are and are never in here.
struct ShelfStorage: Sendable {
    static let shared = ShelfStorage(
        directory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Symbiodock/Shelf", isDirectory: true))

    let directory: URL

    /// Symlinks resolved, so that `/var` and `/private/var` compare equal.
    private func path(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    /// A new, empty `<directory>/<uuid>/`.
    func newFolder() throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Whether the url is inside the storage (the storage itself is not).
    func owns(_ url: URL) -> Bool {
        path(url).hasPrefix(path(directory) + "/")
    }

    /// The uuid folder that holds the url, if it is owned.
    private func folder(holding url: URL) -> URL? {
        guard owns(url) else { return nil }
        let base = path(directory)
        let first = path(url).dropFirst(base.count + 1).split(separator: "/").first
        return first.map { directory.appendingPathComponent(String($0), isDirectory: true) }
    }

    /// Removes the uuid folder holding the url; a url somewhere else is left alone.
    func discard(_ url: URL) {
        guard let folder = folder(holding: url) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Removes every folder that holds none of the urls: what an earlier run left behind.
    func purgeOrphans(keeping urls: [URL]) {
        let kept = Set(urls.compactMap { folder(holding: $0).map(path) })
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !kept.contains(path(folder)) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
