import Darwin
import Foundation
import SymbiodockCore
import SystemConfiguration

/// Where this Mac is on its network.
struct LANRoute: Equatable, Sendable {
    /// The primary interface's name, such as "en0": a sweep is bound to it.
    var interface: String
    var router: LANAddress?
    var own: LANAddress
    var mask: LANAddress
}

/// Reads what the system already knows about the network. Nothing is sent, and no
/// permission is needed: macOS gives an app its neighbour table as it stands.
enum LANReader {
    /// The primary interface's address, mask and router; nil without a network.
    static func route(store: SCDynamicStore?) -> LANRoute? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any],
              let interface = global["PrimaryInterface"] as? String,
              let own = SCDynamicStoreCopyValue(
                  store, "State:/Network/Interface/\(interface)/IPv4" as CFString) as? [String: Any],
              let address = (own["Addresses"] as? [String])?.first.flatMap(LANAddress.init),
              let mask = (own["SubnetMasks"] as? [String])?.first.flatMap(LANAddress.init)
        else { return nil }
        return LANRoute(
            interface: interface,
            router: (global["Router"] as? String).flatMap(LANAddress.init), own: address, mask: mask)
    }

    /// The IPv4 neighbour table's bytes; empty when it cannot be read.
    static func neighbourDump() -> [UInt8] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
        // Room to spare: the table may grow between the two calls.
        length += 4096
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [] }
        return Array(buffer.prefix(length))
    }
}
