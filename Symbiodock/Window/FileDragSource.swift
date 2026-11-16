import AppKit
import os

/// The source of files dragged out of the shelf. The app that takes the drop decides between
/// copying and moving, as with a drag from Finder; dropped back on the island, the files move
/// between its stacks.
@MainActor
final class FileDragSource: NSObject, NSDraggingSource {
    /// File drag milestones (counts, ids and booleans, never names). The same category as the
    /// drop side, so one stream follows a drag from the press to where it lands. Watch with:
    /// `log stream --level debug --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "drop"'`
    nonisolated static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "drop")

    /// What another app may do with the files.
    private let outsideOperations: NSDragOperation
    /// Every move of the drag: the island re-checks the pointer, so that once the drag leaves
    /// it the panel lets events through and the drop reaches the app below.
    private let onMoved: @MainActor () -> Void
    /// The drag is over; `[]` when it was cancelled or nothing took it.
    private let onEnded: @MainActor (_ operation: NSDragOperation) -> Void

    init(
        outsideOperations: NSDragOperation, onMoved: @escaping @MainActor () -> Void,
        onEnded: @escaping @MainActor (_ operation: NSDragOperation) -> Void
    ) {
        self.outsideOperations = outsideOperations
        self.onMoved = onMoved
        self.onEnded = onEnded
    }

    /// No `.delete`: the Trash is not offered. No `.link` when a file lives in the shelf's own
    /// storage: an alias to it would break once the storage is cleaned.
    static func outsideOperations(for urls: [URL], storage: ShelfStorage = .shared) -> NSDragOperation {
        urls.contains(where: storage.owns) ? [.copy, .move, .generic] : [.copy, .move, .link, .generic]
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        case .outsideApplication: outsideOperations
        // Within the island the files only ever change stacks.
        case .withinApplication: .move
        @unknown default: []
        }
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        onMoved()
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        onEnded(operation)
    }
}
