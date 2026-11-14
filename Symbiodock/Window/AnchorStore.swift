import Foundation
import SymbiodockCore

/// Remembers where the island was docked, across launches.
enum AnchorStore {
    private static let key = "islandAnchor"

    /// Anything unreadable falls back to the notch.
    static func load() -> IslandAnchor {
        AnchorCodec.decode(UserDefaults.standard.data(forKey: key))
    }

    static func save(_ anchor: IslandAnchor) {
        UserDefaults.standard.set(AnchorCodec.encode(anchor), forKey: key)
    }
}
