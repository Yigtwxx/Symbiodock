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

public enum LANDevices {
    /// The devices among the neighbours: those with a hardware address that is a device's.
    /// The router first, this Mac second (listed even if the table does not hold it), then
    /// the named ones by name, then the rest by address.
    public static func list(
        neighbours: [LANNeighbour], router: LANAddress?, own: LANAddress?, names: [LANAddress: String]
    ) -> [LANDevice] {
        var seen: Set<LANAddress> = []
        var devices: [LANDevice] = []
        for neighbour in neighbours where isDevice(neighbour) && seen.insert(neighbour.address).inserted {
            let kind: LANDevice.Kind =
                neighbour.address == own ? .thisMac : neighbour.address == router ? .router : .other
            devices.append(LANDevice(address: neighbour.address, name: names[neighbour.address], kind: kind))
        }
        if let own, !seen.contains(own) {
            devices.append(LANDevice(address: own, name: names[own], kind: .thisMac))
        }
        return devices.sorted(by: precedes)
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
    /// "Living-Room-TV.local." → "Living Room TV": the first label, its hyphens as spaces.
    /// Nil when nothing readable is left.
    public static func display(_ host: String) -> String? {
        let label = host.split(separator: ".", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let words = label.split(separator: "-", omittingEmptySubsequences: true)
        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// A domain name as DNS carries it: labels, each led by its length, up to a zero.
    /// Nil for an empty name, a label that runs past the end, or a compression pointer.
    public static func host(fromWire bytes: [UInt8]) -> String? {
        var labels: [String] = []
        var index = 0
        while index < bytes.count, bytes[index] != 0 {
            let count = Int(bytes[index])
            guard count < 64, index + 1 + count <= bytes.count else { return nil }
            labels.append(String(decoding: bytes[(index + 1)..<(index + 1 + count)], as: UTF8.self))
            index += 1 + count
        }
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }

    /// The name to ask for to learn an address's host name: "7.1.168.192.in-addr.arpa".
    public static func reverseQuestion(for address: LANAddress) -> String {
        address.bytes.reversed().map(String.init).joined(separator: ".") + ".in-addr.arpa"
    }
}

/// How a sweep's packets fared.
public struct SweepOutcome: Equatable, Sendable {
    public var sent: Int
    /// Sends the system refused with "no route to host": what it answers while the Local
    /// Network permission is missing.
    public var refused: Int

    public init(sent: Int, refused: Int) {
        self.sent = sent
        self.refused = refused
    }

    /// Whether macOS kept the sweep back: nine in ten sends, or more, were refused.
    public var isBlocked: Bool {
        refused > 0 && refused * 10 >= (sent + refused) * 9
    }
}

public enum LANLabels {
    /// "1 device", "6 devices".
    public static func count(_ devices: Int) -> String {
        devices == 1 ? "1 device" : "\(devices) devices"
    }
}
