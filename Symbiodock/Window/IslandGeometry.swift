import CoreGraphics
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
}
