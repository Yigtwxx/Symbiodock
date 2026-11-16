#if DEBUG
import Foundation
import SymbiodockCore

/// A fixed shelf for looking at the Files tab without dropping anything:
/// `open --env SYMBIODOCK_DEMO_FILES=1 build/Build/Products/Debug/Symbiodock.app`.
/// `converting` also starts a conversion of the selected item. The files are not there, and
/// a demo shelf is never saved.
///
/// `SYMBIODOCK_CONVERT=<path> SYMBIODOCK_CONVERT_TO=<chip label>` runs one conversion without
/// the island, prints `converted: <path>` or `failed: <message>` and exits 0 / 1 (see
/// `ConvertHook`). Several paths separated by `:` with `ZIP` call `archive`.
/// `SYMBIODOCK_CONVERT_CANCEL_AFTER=<seconds>` cancels it part way.
///
/// `SYMBIODOCK_ADD_FILE=<path>` puts that file on the real shelf at launch, as a drop would:
/// run once with it, quit, run again without it, and the log line "restored 1 items" (category
/// `shelf`) shows that the shelf came back. It stays as a test hook.
@MainActor
enum DemoFiles {
    static var requested: String? {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_FILES"].flatMap {
            ["1", "converting"].contains($0) ? $0 : nil
        }
    }

    static var fileToAdd: URL? {
        ProcessInfo.processInfo.environment["SYMBIODOCK_ADD_FILE"].map {
            URL(fileURLWithPath: $0)
        }
    }

    static func apply(_ set: String, to state: IslandState, now: Date = Date()) {
        let desktop = URL(fileURLWithPath: "/Users/demo/Desktop", isDirectory: true)
        let names: [(String, Bool)] = [
            ("Holiday.heic", false), ("Report.docx", false), ("Invoice.pdf", false),
            ("Mix.wav", false), ("Clip.mov", false), ("Photos", true),
        ]
        state.restoreShelf(
            names.map { ShelfItem(url: desktop.appendingPathComponent($0.0), isDirectory: $0.1) })
        if set == "converting", let id = state.shelf.selectedID {
            state.beginConversion(id, label: "PNG", at: now)
        }
    }
}

/// Runs one conversion headless and exits by itself; the way to try the converters without
/// a tile to press. Nothing is shown, so no window or permission dialog can appear.
@MainActor
enum ConvertHook {
    /// True when the hook took over: the caller must not build the island.
    static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let paths = environment["SYMBIODOCK_CONVERT"],
            let chip = environment["SYMBIODOCK_CONVERT_TO"]
        else { return false }
        let sources = paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        let cancelAfter = environment["SYMBIODOCK_CONVERT_CANCEL_AFTER"].flatMap(Double.init)
        let converter = FileConverter(runner: ToolRunner(helpers: HelperProcesses()))

        let work = Task { () -> String? in
            do {
                if chip == "ZIP" && sources.count > 1 {
                    return "converted: \(try await converter.archive(sources).path)"
                }
                guard let source = sources.first else { return nil }
                let isDirectory =
                    (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let targets = ConversionCatalog.targets(
                    pathExtension: source.pathExtension, isDirectory: isDirectory)
                guard let target = targets.first(where: { $0.label == chip }) else {
                    return "failed: no such chip"
                }
                let result = try await converter.convert(
                    source, isDirectory: isDirectory, to: target)
                return "converted: \(result.url.path)"
            } catch is CancellationError {
                return "failed: cancelled"
            } catch let failure as ConversionFailure {
                return "failed: \(failure.message)"
            } catch {
                return "failed: unknown"
            }
        }
        if let cancelAfter {
            Task {
                try? await Task.sleep(for: .seconds(cancelAfter))
                work.cancel()
            }
        }
        Task {
            let line = await work.value ?? "failed: nothing to convert"
            print(line)
            fflush(stdout)
            exit(line.hasPrefix("converted") ? 0 : 1)
        }
        return true
    }
}
#endif
