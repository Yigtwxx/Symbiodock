#if DEBUG
import Foundation
import SymbiodockCore

/// A fixed shelf for looking at the Files tab without dropping anything:
/// `open --env SYMBIODOCK_DEMO_FILES=1 build/Build/Products/Debug/Symbiodock.app`.
/// `converting` also starts a conversion of the selected item. The files are not there, and
/// a demo shelf is never saved.
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
#endif
