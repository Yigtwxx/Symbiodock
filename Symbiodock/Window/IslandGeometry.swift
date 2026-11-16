import CoreGraphics
import Foundation
import Observation

/// The display facts the island is laid out against, in panel-local coordinates.
/// Observable so views follow a Dock or menu bar change without the panel being rebuilt.
@MainActor
@Observable
final class IslandGeometry {
    var notch: CGRect = .zero
    var visibleFrame: CGRect = .zero
    var screenSize: CGSize = .zero
    /// False on displays where the notch is only a stand-in drawn by us.
    var hasPhysicalNotch = false
    /// Where a press must not start dragging the island (a slider), in panel-local
    /// coordinates. Written during layout, so it is not observed.
    @ObservationIgnored var noDragRects: [String: CGRect] = [:]
    /// The Files page's tiles by item, panel-local: a press on one drags its file out
    /// instead of the island. Written during layout, so it is not observed.
    @ObservationIgnored var fileDragRects: [UUID: CGRect] = [:]
    /// The visible part of the tile row; a tile scrolled out of it is not under the pointer.
    @ObservationIgnored var fileDragViewport: CGRect = .null
}
