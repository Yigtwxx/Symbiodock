import AppKit
import os

/// The source of a tile's file dragged out of the island. The app that takes the drop decides
/// between copying and moving, as with a drag from Finder; the island itself takes nothing back.
@MainActor
final class FileDragSource: NSObject, NSDraggingSource {
    /// File drag milestones (ids and booleans, never names). Watch with:
    /// `log stream --level debug --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "file-drag"'`
    nonisolated static let log = Logger(subsystem: "com.yigtwxx.Symbiodock", category: "file-drag")

    /// Every move of the drag: the island re-checks the pointer, so that once the drag leaves
    /// it the panel lets events through and the drop reaches the app below.
    var onMoved: @MainActor () -> Void
    /// The drag is over; `dropped` is false when it was cancelled or nothing took it.
    var onEnded: @MainActor (_ dropped: Bool) -> Void

    init(onMoved: @escaping @MainActor () -> Void, onEnded: @escaping @MainActor (_ dropped: Bool) -> Void) {
        self.onMoved = onMoved
        self.onEnded = onEnded
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        switch context {
        // No `.delete`: the Trash is not offered.
        case .outsideApplication: [.copy, .move, .link, .generic]
        // Dropped back on the island, the drag is cancelled and the tile stays.
        case .withinApplication: []
        @unknown default: []
        }
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        onMoved()
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        onEnded(operation != [])
    }
}
