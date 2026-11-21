import Foundation

/// An IPv4 address.
public struct LANAddress: Hashable, Comparable, Sendable {
    /// In host order: 192.168.1.7 is 0xC0A80107.
    public let value: UInt32

    public init(value: UInt32) {
        self.value = value
    }

    public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        value = UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }

    /// "192.168.1.7"; nil for anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber),
                  let byte = UInt8(part)
            else { return nil }
            value = value << 8 | UInt32(byte)
        }
        self.value = value
    }

    public var bytes: [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    public var text: String {
        bytes.map(String.init).joined(separator: ".")
    }

    /// ".7": what a row shows beside a device's name.
    public var suffix: String {
        ".\(value & 0xFF)"
    }

    public static func < (lhs: LANAddress, rhs: LANAddress) -> Bool {
        lhs.value < rhs.value
    }
}

/// The addresses a scan sends to.
public enum SubnetSweep {
    /// A /22. A wider subnet is an office or a campus, not a home: it is not swept.
    public static let maximumHosts = 1022

    /// Every host address of the subnet except this Mac's own; the network and broadcast
    /// addresses are left out. Empty when the subnet is too wide, holds nobody else, or the
    /// mask is not a mask.
    public static func hosts(own: LANAddress, mask: LANAddress) -> [LANAddress] {
        let hostBits = ~mask.value
        // A mask is ones followed by zeros: its complement plus one is a power of two.
        guard hostBits & (hostBits &+ 1) == 0, hostBits >= 3, hostBits - 1 <= UInt32(maximumHosts)
        else { return [] }
        let network = own.value & mask.value
        return (1..<hostBits).compactMap { offset in
            let host = network | offset
            return host == own.value ? nil : LANAddress(value: host)
        }
    }
}
