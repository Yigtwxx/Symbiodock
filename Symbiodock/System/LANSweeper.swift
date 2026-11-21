import Darwin
import Foundation
import SymbiodockCore

/// Sends one empty UDP datagram to each address, so that the kernel asks who has it; those
/// that answer get a hardware address in the neighbour table. The first time, this is what
/// makes macOS ask for the Local Network permission. Only ever called for a scan the owner
/// asked for.
enum LANSweeper {
    /// The discard port: nothing answers it, and nothing needs to.
    private static let port: UInt16 = 9

    /// Sends through `interface` only: with a full-tunnel VPN the primary interface is a
    /// tunnel, and nothing may be swept into one. Returns the addresses the system refused.
    static func sweep(_ hosts: [LANAddress], interface: String) -> SweepOutcome {
        var index = if_nametoindex(interface)
        var outcome = SweepOutcome(sent: 0, refused: [])
        guard index != 0 else { return outcome }
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return outcome }
        defer { close(descriptor) }
        // Not bound: not sent. The datagrams would otherwise follow the routing table.
        guard setsockopt(
            descriptor, IPPROTO_IP, IP_BOUND_IF, &index, socklen_t(MemoryLayout<UInt32>.size)) == 0
        else { return outcome }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        for host in hosts {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = port.bigEndian
            target.sin_addr.s_addr = host.value.bigEndian
            let result = withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, nil, 0, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result >= 0 {
                outcome.sent += 1
            } else if errno == EHOSTUNREACH {
                outcome.refused.insert(host)
            }
        }
        return outcome
    }
}
