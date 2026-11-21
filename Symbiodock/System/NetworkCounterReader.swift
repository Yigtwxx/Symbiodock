import Darwin
import Foundation
import SymbiodockCore
import SystemConfiguration

/// The byte counters of the interface the default route uses. No permission is needed.
enum NetworkCounterReader {
    /// Nil while there is no network, and when the counters cannot be read.
    static func counters(store: SCDynamicStore?) -> NetworkCounters? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any],
              let interface = global["PrimaryInterface"] as? String
        else { return nil }
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        // The 64-bit counters; `getifaddrs` gives 32-bit ones that wrap at 4 GB.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        // Room to spare: an address added between the two calls must not fail the read, which
        // would show the Mac as offline for a sample.
        length += 512
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self) }
            guard header.ifm_msglen > 0 else { break }
            if Int32(header.ifm_type) == RTM_IFINFO2, UInt32(header.ifm_index) == index,
               offset + MemoryLayout<if_msghdr2>.size <= length {
                let full = buffer.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                }
                return NetworkCounters(
                    interface: interface, received: full.ifm_data.ifi_ibytes, sent: full.ifm_data.ifi_obytes)
            }
            offset += Int(header.ifm_msglen)
        }
        return nil
    }
}
