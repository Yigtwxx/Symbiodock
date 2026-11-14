import Foundation

/// A file's size and modification time: enough to tell whether it has to be read again.
struct FileStamp: Equatable, Sendable {
    let size: Int
    let modified: Date
}

/// Reads of other tools' files. Every read is bounded and read-only; a failure is nil.
enum FileReading {
    static func stamp(of url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return FileStamp(size: size, modified: modified)
    }

    /// The whole file, or nil if it is larger than `maxBytes`.
    static func whole(_ url: URL, maxBytes: Int) -> Data? {
        guard let stamp = stamp(of: url), stamp.size <= maxBytes else { return nil }
        return head(of: url, maxBytes: maxBytes)
    }

    /// At most the first `maxBytes` bytes.
    static func head(of url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes)
    }

    /// At most the last `maxBytes` bytes.
    static func tail(of url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        return try? handle.read(upToCount: maxBytes)
    }
}
