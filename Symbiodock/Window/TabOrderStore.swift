import Foundation
import SymbiodockCore

/// Remembers the order of the tabs across launches.
enum TabOrderStore {
    private static let key = "tabOrder"

    /// Anything missing or unreadable gives the default order.
    static func load() -> [IslandTab] {
        TabOrder.repaired(UserDefaults.standard.stringArray(forKey: key))
    }

    static func save(_ order: [IslandTab]) {
        UserDefaults.standard.set(TabOrder.encode(order), forKey: key)
    }
}
