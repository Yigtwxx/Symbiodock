import Darwin
import Foundation

/// A file's size and times: enough to tell whether it has to be read again.
struct FileStamp: Equatable, Sendable {
    let size: Int
    let modified: Date
    /// When the file was created. A file replaced by a rename gets a new one.
    let created: Date
}

/// Reads of other tools' files. Every read is bounded and read-only; a failure is nil.
enum FileReading {
    /// A plain `stat`: `FileManager.attributesOfItem` also reads extended attributes,
    /// which made it the most expensive part of a scan.
    static func stamp(of url: URL) -> FileStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        func date(_ time: timespec) -> Date {
            Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
        }
        return FileStamp(
            size: Int(info.st_size), modified: date(info.st_mtimespec), created: date(info.st_birthtimespec))
    }

    /// The whole file, or nil if it is larger than `maxBytes`.
    static func whole(_ url: URL, maxBytes: Int) -> Data? {
        guard let stamp = stamp(of: url), stamp.size <= maxBytes else { return nil }
        return head(of: url, maxBytes: maxBytes)
    }

    /// At most the first `maxBytes` bytes.
    static func head(of url: URL, maxBytes: Int) -> Data? {
        guard maxBytes > 0, let handle = openRegularFile(url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes)
    }

    /// At most the last `maxBytes` bytes.
    static func tail(of url: URL, maxBytes: Int) -> Data? {
        guard maxBytes > 0, let handle = openRegularFile(url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return nil }
        return try? handle.read(upToCount: maxBytes)
    }

    /// Opens a file for reading only if it is a regular file. The check is made on the
    /// open descriptor, so what was checked is what is read. A pipe or a device at the
    /// path would block the scan; it is opened without waiting (`O_NONBLOCK` lets the
    /// open of a pipe return at once) and then turned away.
    private static func openRegularFile(_ url: URL) -> FileHandle? {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            return nil
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
