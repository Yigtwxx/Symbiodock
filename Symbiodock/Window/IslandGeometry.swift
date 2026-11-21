import CoreGraphics
import Foundation
import Observation
import SymbiodockCore

/// The display facts the island is laid out against, in panel-local coordinates.
/// Observable so views follow a Dock change without the panel being rebuilt.
@MainActor
@Observable
final class IslandGeometry {
    var notch: CGRect = .zero
    /// The area the island docks against (`ScreenMetrics.localDockFrame`). Since 2026-11-21
    /// the whole display, not the system's visible frame: the island lies on the bezel.
    var visibleFrame: CGRect = .zero
    /// The Dock, while it takes up room on this display: over it the island rests on the Dock.
    var dock: DockObstacle?
    var screenSize: CGSize = .zero
    /// False on displays where the notch is only a stand-in drawn by us.
    var hasPhysicalNotch = false
    /// Where a press must not start dragging the island (a slider), in panel-local
    /// coordinates. Written during layout, so it is not observed.
    @ObservationIgnored var noDragRects: [String: CGRect] = [:]
    /// The Files page's stacks by stack id: each stack's box, panel-local. A press on one drags
    /// its files out instead of the island, and the pointer over one lifts its cards. Written
    /// during layout, so it is not observed.
    @ObservationIgnored private(set) var fileDragRects: [UUID: CGRect] = [:]
    /// The visible part of the tile row; a stack scrolled out of it is not under the pointer.
    @ObservationIgnored private(set) var fileDragViewport: CGRect = .null

    /// Which view instance wrote each rect. A view that is replaced can disappear after its
    /// replacement has written the same key; it must not take the newer rect away with it.
    @ObservationIgnored private var fileDragOwners: [UUID: UUID] = [:]
    @ObservationIgnored private var viewportOwner: UUID?

    func publishFileDragRect(_ rect: CGRect, for stack: UUID, by owner: UUID) {
        fileDragRects[stack] = rect
        fileDragOwners[stack] = owner
    }

    func withdrawFileDragRect(for stack: UUID, by owner: UUID) {
        guard fileDragOwners[stack] == owner else { return }
        fileDragRects[stack] = nil
        fileDragOwners[stack] = nil
    }

    func publishFileDragViewport(_ rect: CGRect, by owner: UUID) {
        fileDragViewport = rect
        viewportOwner = owner
    }

    func withdrawFileDragViewport(by owner: UUID) {
        guard viewportOwner == owner else { return }
        fileDragViewport = .null
        viewportOwner = nil
    }
}
