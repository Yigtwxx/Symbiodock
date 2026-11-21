import Foundation

/// A device on the network, as the System tab lists it.
public struct LANDevice: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case router
        case thisMac
        case other
    }

    public var address: LANAddress
    /// The name the device gave, already made readable; nil when it gave none.
    public var name: String?
    public var kind: Kind

    public init(address: LANAddress, name: String?, kind: Kind) {
        self.address = address
        self.name = name
        self.kind = kind
    }

    public var id: LANAddress { address }

    /// What the row says: the role, the name, or the address when there is neither.
    public var title: String {
        switch kind {
        case .router: "Router"
        case .thisMac: "This Mac"
        case .other: name ?? address.text
        }
    }

    /// False when the title is only the address: the row then does not repeat its end.
    public var isNamed: Bool {
        kind != .other || name != nil
    }
}

/// What a device is known by across scans: its address together with its hardware address.
/// An address alone is not a device: on another network, or after a new lease, the same
/// address belongs to someone else.
public struct LANIdentity: Hashable, Sendable {
    public var address: LANAddress
    public var hardware: [UInt8]

    public init(address: LANAddress, hardware: [UInt8]) {
        self.address = address
        self.hardware = hardware
    }
}

public enum LANDevices {
    /// The devices among the neighbours: those with a hardware address that is a device's.
    /// The router first, this Mac second (listed even if the table does not hold it), then
    /// the named ones by name, then the rest by address.
    public static func list(
        neighbours: [LANNeighbour], router: LANAddress?, own: LANAddress?, names: [LANIdentity: String]
    ) -> [LANDevice] {
        var seen: Set<LANAddress> = []
        var rows: [LANDevice] = []
        for neighbour in devices(among: neighbours) {
            seen.insert(neighbour.address)
            let kind: LANDevice.Kind =
                neighbour.address == own ? .thisMac : neighbour.address == router ? .router : .other
            let name = neighbour.hardware.flatMap {
                names[LANIdentity(address: neighbour.address, hardware: $0)]
            }
            rows.append(LANDevice(address: neighbour.address, name: name, kind: kind))
        }
        // This Mac's row is titled by its role, so it needs no name.
        if let own, !seen.contains(own) {
            rows.append(LANDevice(address: own, name: nil, kind: .thisMac))
        }
        return rows.sorted(by: precedes)
    }

    /// The neighbours that are devices, one per address: the first entry of an address wins.
    public static func devices(among neighbours: [LANNeighbour]) -> [LANNeighbour] {
        var seen: Set<LANAddress> = []
        return neighbours.filter { isDevice($0) && seen.insert($0.address).inserted }
    }

    /// Whether the network is one a scan may be sent into: a subnet that is swept at all, and
    /// a router in it that has a hardware address in the table. That proves a network that
    /// speaks ARP; a tunnel (a VPN) has no such entry, and a scan must not go into one.
    public static func canScan(
        neighbours: [LANNeighbour], router: LANAddress?, own: LANAddress, mask: LANAddress
    ) -> Bool {
        guard let router, !SubnetSweep.hosts(own: own, mask: mask).isEmpty,
              router.value & mask.value == own.value & mask.value
        else { return false }
        return devices(among: neighbours).contains { $0.address == router }
    }

    private static func isDevice(_ neighbour: LANNeighbour) -> Bool {
        guard let hardware = neighbour.hardware, hardware.count == 6 else { return false }
        // Multicast groups and the broadcast address have entries too.
        guard neighbour.address.value >> 28 < 14 else { return false }
        // All ones is broadcast, all zeros is unset, an odd first byte is a group address.
        return hardware != [UInt8](repeating: 0xFF, count: 6) && hardware != [UInt8](repeating: 0, count: 6)
            && hardware[0] & 1 == 0
    }

    private static func rank(_ device: LANDevice) -> Int {
        switch device.kind {
        case .router: 0
        case .thisMac: 1
        case .other: device.name == nil ? 3 : 2
        }
    }

    private static func precedes(_ lhs: LANDevice, _ rhs: LANDevice) -> Bool {
        let (left, right) = (rank(lhs), rank(rhs))
        if left != right { return left < right }
        if left == 2 {
            let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if order != .orderedSame { return order == .orderedAscending }
        }
        return lhs.address < rhs.address
    }
}

/// Device names: from the wire, and into what a person would call the device.
public enum LANNames {
    /// A shown name is never longer than this.
    public static let maximumLength = 40

    /// "Living-Room-TV.local." → "Living Room TV": the first label, its hyphens as spaces.
    /// Nil when nothing readable is left.
    ///
    /// The name comes from another device on the network, so it is not trusted: control and
    /// format characters (line breaks, direction overrides) are dropped and the length is
    /// capped before it is shown.
    public static func display(_ host: String) -> String? {
        let label = host.split(separator: ".", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let safe = String(String.UnicodeScalarView(label.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator:
                false
            default:
                true
            }
        }))
        let words = safe.split(separator: "-", omittingEmptySubsequences: true)
        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name.prefix(maximumLength))
    }

    /// A domain name as DNS carries it: labels, each led by its length, up to a zero.
    /// Nil for an empty name, a label that runs past the end, a name cut off before its
    /// closing zero, or a compression pointer.
    public static func host(fromWire bytes: [UInt8]) -> String? {
        var labels: [String] = []
        var index = 0
        while index < bytes.count, bytes[index] != 0 {
            let count = Int(bytes[index])
            guard count < 64, index + 1 + count <= bytes.count else { return nil }
            labels.append(String(decoding: bytes[(index + 1)..<(index + 1 + count)], as: UTF8.self))
            index += 1 + count
        }
        // The bytes ran out before the closing zero: the answer was cut short.
        guard index < bytes.count, !labels.isEmpty else { return nil }
        return labels.joined(separator: ".")
    }

    /// The name to ask for to learn an address's host name: "7.1.168.192.in-addr.arpa".
    public static func reverseQuestion(for address: LANAddress) -> String {
        address.bytes.reversed().map(String.init).joined(separator: ".") + ".in-addr.arpa"
    }
}

/// How a sweep's packets fared.
public struct SweepOutcome: Equatable, Sendable {
    public var sent: Int
    /// The addresses the system refused with "no route to host".
    public var refused: Set<LANAddress>

    public init(sent: Int, refused: Set<LANAddress>) {
        self.sent = sent
        self.refused = refused
    }

    /// Whether macOS kept the sweep back for want of the Local Network permission.
    /// - Parameter witnesses: addresses that had a hardware address before the sweep, this
    ///   Mac and the router left out. The kernel does not refuse those by itself, so if
    ///   there are any, they decide: blocked when any of them was refused. Without
    ///   any, nine in ten refusals, or more, count as blocked.
    public func isBlocked(witnesses: Set<LANAddress>) -> Bool {
        // The kernel also answers "no route" for an address that stayed silent through several
        // ARP requests, so on repeated scans of a quiet range most refusals are its own.
        // One refused witness is enough: the kernel never refuses a device it holds an address
        // for, so only the missing permission can have done it. (Asking for all of them would
        // miss the permission if the system lets one address through.)
        if !witnesses.isEmpty { return !witnesses.isDisjoint(with: refused) }
        return !refused.isEmpty && refused.count * 10 >= (sent + refused.count) * 9
    }
}

public enum LANLabels {
    /// "1 device", "6 devices".
    public static func count(_ devices: Int) -> String {
        devices == 1 ? "1 device" : "\(devices) devices"
    }
}

/// Where a scan of the network stands.
public enum LANScanState: Equatable, Sendable {
    case idle
    /// Asked for and not finished.
    case scanning
    /// The last scan was kept back by macOS: the Local Network permission is missing.
    case blocked
}
