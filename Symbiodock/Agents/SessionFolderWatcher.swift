import CoreServices
import Foundation

/// Calls back on the main actor soon after anything in a folder changes, so that a
/// session's new status is seen at once instead of on the next timed scan. It only
/// listens: FSEvents reports the changes without the folder being opened or written.
@MainActor
final class SessionFolderWatcher {
    /// Carries the handler into the C callback, which runs on `queue`.
    private final class Relay: Sendable {
        let onChange: @MainActor @Sendable () -> Void

        init(_ onChange: @escaping @MainActor @Sendable () -> Void) {
            self.onChange = onChange
        }

        func fire() {
            let onChange = onChange
            Task { @MainActor in onChange() }
        }
    }

    private let path: String
    private let relay: Relay
    private let queue = DispatchQueue(label: "com.yigtwxx.Symbiodock.session-folder", qos: .utility)
    private var stream: FSEventStreamRef?

    init(folder: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        path = folder.path
        relay = Relay(onChange)
    }

    /// Starts listening unless it already does. False while the folder does not exist;
    /// the caller tries again later.
    @discardableResult
    func start() -> Bool {
        if stream != nil { return true }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        // The watcher outlives its stream (`stop()` ends it), so the relay needs no retain.
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(relay).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Relay>.fromOpaque(info).takeUnretainedValue().fire()
            },
            &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags)
        else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
