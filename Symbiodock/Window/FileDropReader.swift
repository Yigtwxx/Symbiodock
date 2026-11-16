import AppKit
import os

/// Reads what a drag onto the island carries: file and folder URLs; files an app promises but
/// has not written yet (an image from Safari, Photos, a Mail attachment); raw image data.
/// Promised and raw pieces are written into the shelf's own storage, one folder each.
enum FileDropReader {
    /// Milestones and failures (counts, error codes), never names or contents. Watch with:
    /// `log stream --level debug --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "drop"'`
    static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "drop")

    /// Raw image data, preferred first: PNG is written as it comes.
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    static var types: [NSPasteboard.PasteboardType] {
        [.fileURL]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
            + imageTypes
    }

    @MainActor
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            || pasteboard.availableType(from: imageTypes) != nil
    }

    /// File URLs at once; promised files and raw images as they arrive. False if nothing usable.
    @MainActor
    static func read(
        _ pasteboard: NSPasteboard, storage: ShelfStorage,
        deliver: @escaping @MainActor ([URL]) -> Void
    ) -> Bool {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        {
            log.notice("read \(urls.count) file urls")
            deliver(urls)
            return true
        }
        if let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
            !receivers.isEmpty
        {
            return receive(receivers, storage: storage, deliver: deliver)
        }
        if let type = pasteboard.availableType(from: imageTypes), let data = pasteboard.data(forType: type) {
            log.notice("read raw image data (\(type.rawValue, privacy: .public))")
            let isPNG = type == .png
            Task.detached(priority: .userInitiated) {
                guard let url = writeImage(data, isPNG: isPNG, storage: storage) else { return }
                await deliver([url])
            }
            return true
        }
        log.notice("nothing usable on the pasteboard")
        return false
    }

    // MARK: Promised files

    /// One queue for every promise, so that files are settled one at a time.
    @MainActor private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.yigtwxx.Symbiodock.promises"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    @MainActor
    private static func receive(
        _ receivers: [NSFilePromiseReceiver], storage: ShelfStorage,
        deliver: @escaping @MainActor ([URL]) -> Void
    ) -> Bool {
        // AppKit wants one destination for every promise of a drag. Each file then moves to a
        // folder of its own, so that removing its tile removes exactly that file; the emptied
        // landing folder is cleaned at the next launch with the other orphans.
        let landing: URL
        do {
            landing = try storage.newFolder()
        } catch {
            log.error("could not make a folder for promised files: \(describe(error), privacy: .public)")
            return false
        }
        log.notice("receiving \(receivers.count) promised files")
        for receiver in receivers {
            // Called on `promiseQueue`, not the main actor: written out so that the closure does
            // not take this function's isolation.
            receiver.receivePromisedFiles(
                atDestination: landing, options: [:], operationQueue: promiseQueue
            ) { @Sendable url, error in
                if let error {
                    log.error("a promised file did not arrive: \(describe(error), privacy: .public)")
                    return
                }
                guard let kept = settle(url, from: landing, storage: storage) else { return }
                Task { await deliver([kept]) }
            }
        }
        return true
    }

    /// Moves a promised file out of the landing folder into a folder of its own. The name is
    /// the promising app's; only a plain name inside the landing folder is taken.
    private static func settle(_ url: URL, from landing: URL, storage: ShelfStorage) -> URL? {
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        guard !name.isEmpty, name != ".", name != "..",
              parent.path == landing.resolvingSymlinksInPath().standardizedFileURL.path
        else {
            log.error("a promised file arrived outside its folder; ignored")
            return nil
        }
        do {
            let destination = try storage.newFolder().appendingPathComponent(name)
            try FileManager.default.moveItem(at: url, to: destination)
            log.notice("a promised file arrived")
            return destination
        } catch {
            log.error("could not keep a promised file: \(describe(error), privacy: .public)")
            return nil
        }
    }

    // MARK: Raw images

    /// Written off the main actor: a large TIFF takes a moment to encode.
    private static func writeImage(_ data: Data, isPNG: Bool, storage: ShelfStorage) -> URL? {
        guard let png = isPNG
            ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        else {
            log.error("image data could not be read")
            return nil
        }
        do {
            let url = try storage.newFolder().appendingPathComponent("Image.png")
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            log.error("could not write a dropped image: \(describe(error), privacy: .public)")
            return nil
        }
    }

    /// Domain and code only: a description may name the file.
    private static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}
