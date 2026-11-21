import Foundation

/// One entry of the kernel's IPv4 neighbour table (what `arp -a` lists).
public struct LANNeighbour: Equatable, Sendable {
    public var address: LANAddress
    /// The hardware address. Nil while nobody has answered for the address: after a sweep
    /// the kernel holds such an entry for every address that was tried.
    public var hardware: [UInt8]?

    public init(address: LANAddress, hardware: [UInt8]?) {
        self.address = address
        self.hardware = hardware
    }
}

/// Reads the bytes `sysctl` returns for `NET_RT_FLAGS` + `RTF_LLINFO`: route messages, each a
/// header followed by the destination (`sockaddr_in`) and the gateway (`sockaddr_dl`).
/// Anything unexpected ends the walk or skips the entry; nothing here can trap.
public enum NeighbourTable {
    /// The size of `rt_msghdr`.
    public static let headerSize = MemoryLayout<rt_msghdr>.size

    private static let inetFamily = UInt8(AF_INET)
    private static let linkFamily = UInt8(AF_LINK)

    public static func neighbours(fromRouteDump dump: [UInt8]) -> [LANNeighbour] {
        var neighbours: [LANNeighbour] = []
        var offset = 0
        while offset + headerSize <= dump.count {
            // The message's own length, little-endian, is its first field.
            let length = Int(dump[offset]) | Int(dump[offset + 1]) << 8
            guard length >= headerSize, offset + length <= dump.count else { break }
            let end = offset + length
            defer { offset = end }
            let inet = offset + headerSize
            guard inet + 8 <= end, dump[inet + 1] == inetFamily else { continue }
            let address = LANAddress(dump[inet + 4], dump[inet + 5], dump[inet + 6], dump[inet + 7])
            // Socket addresses are padded to four bytes; an empty one still takes four.
            let link = inet + max(4, (Int(dump[inet]) + 3) & ~3)
            guard link + 8 <= end, dump[link + 1] == linkFamily else { continue }
            // A link-layer address holds the interface's name, then the hardware address.
            let nameLength = Int(dump[link + 5])
            let hardwareLength = Int(dump[link + 6])
            let start = link + 8 + nameLength
            var hardware: [UInt8]?
            if hardwareLength > 0, start + hardwareLength <= end {
                hardware = Array(dump[start..<(start + hardwareLength)])
            }
            neighbours.append(LANNeighbour(address: address, hardware: hardware))
        }
        return neighbours
    }
}
