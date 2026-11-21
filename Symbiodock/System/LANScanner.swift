import Darwin
import Foundation
import SymbiodockCore
import SystemConfiguration

/// What is on the network. `known()` only reads; `scan()` sends, and runs only when the
/// owner asked for it.
actor LANScanner {
    struct Result: Equatable, Sendable {
        var devices: [LANDevice]
        /// Whether this network can be scanned: there is one, and it is not too wide.
        var canScan: Bool
        /// Whether macOS kept the scan's packets back.
        var isBlocked = false
    }

    /// How long a device has to give its name.
    private static let nameTimeout: TimeInterval = 2
    /// The table is read after the answers have had time to arrive.
    private static let settle: Duration = .seconds(1)
    /// At most this many devices are asked for a name in one scan.
    private static let nameLimit = 64

    /// At most this many names are asked for at once: each query holds a thread.
    private static let nameBatch = 16

    private let store = SCDynamicStoreCreate(nil, "Symbiodock" as CFString, nil, nil)
    /// Names learned in scans, until the app quits. Never written anywhere. Kept by address
    /// and hardware address: on another network the same address is someone else.
    private var names: [LANIdentity: String] = [:]
    /// Devices already asked: one that gave no name is not asked on every scan.
    private var asked: Set<LANIdentity> = []

    /// The devices the Mac already knows. Nothing is sent.
    func known() -> Result {
        guard let route = LANReader.route(store: store) else { return Result(devices: [], canScan: false) }
        let neighbours = neighbours(on: route)
        return Result(devices: devices(of: neighbours, on: route), canScan: canScan(route, neighbours))
    }

    /// Sweeps the subnet, then asks the devices that answered for their names.
    func scan() async -> Result {
        guard let route = LANReader.route(store: store) else { return Result(devices: [], canScan: false) }
        let before = neighbours(on: route)
        let hosts = SubnetSweep.hosts(own: route.own, mask: route.mask)
        guard !hosts.isEmpty, canScan(route, before) else {
            return Result(devices: devices(of: before, on: route), canScan: false)
        }
        // Devices that were in the table already: the kernel does not refuse those by itself,
        // so if they are refused, it is the missing permission.
        let witnesses = Set(LANDevices.devices(among: before).map(\.address))
            .subtracting([route.own, route.router].compactMap { $0 })
        let outcome = LANSweeper.sweep(hosts, interface: route.interface)
        if outcome.isBlocked(witnesses: witnesses) {
            return Result(devices: devices(on: route), canScan: true, isBlocked: true)
        }
        try? await Task.sleep(for: Self.settle)
        // Stopped meanwhile: nobody is asked for a name any more.
        guard !Task.isCancelled else { return Result(devices: devices(on: route), canScan: true) }
        // Rows of the router and of this Mac never show a name: they are not asked.
        let toAsk = LANDevices.devices(among: neighbours(on: route))
            .filter { $0.address != route.own && $0.address != route.router }
            .compactMap { neighbour in
                neighbour.hardware.map { LANIdentity(address: neighbour.address, hardware: $0) }
            }
            .filter { !asked.contains($0) }
            .prefix(Self.nameLimit)
        asked.formUnion(toAsk)
        let index = if_nametoindex(route.interface)
        let pending = Array(toAsk)
        for start in stride(from: 0, to: pending.count, by: Self.nameBatch) {
            guard !Task.isCancelled else { break }
            let batch = pending[start..<min(start + Self.nameBatch, pending.count)]
            await withTaskGroup(of: (LANIdentity, String?).self) { group in
                for identity in batch {
                    group.addTask { (identity, await Self.name(of: identity.address, interfaceIndex: index)) }
                }
                for await (identity, host) in group {
                    if let host, let name = LANNames.display(host) { names[identity] = name }
                }
            }
        }
        // A second look: slow devices have answered the sweep by now.
        return Result(devices: devices(on: route), canScan: true)
    }

    /// A subnet that is swept at all, and a router in it that answers ARP: a tunnel has none.
    private func canScan(_ route: LANRoute, _ neighbours: [LANNeighbour]) -> Bool {
        LANDevices.canScan(neighbours: neighbours, router: route.router, own: route.own, mask: route.mask)
    }

    private func neighbours(on route: LANRoute) -> [LANNeighbour] {
        NeighbourTable.neighbours(fromRouteDump: LANReader.neighbourDump())
            // The table also holds neighbours of other interfaces (a VPN, a second network).
            .filter { $0.address.value & route.mask.value == route.own.value & route.mask.value }
    }

    private func devices(on route: LANRoute) -> [LANDevice] {
        devices(of: neighbours(on: route), on: route)
    }

    private func devices(of neighbours: [LANNeighbour], on route: LANRoute) -> [LANDevice] {
        LANDevices.list(neighbours: neighbours, router: route.router, own: route.own, names: names)
    }

    /// The blocking query on a thread of its own, so the waits do not hold the actor or the
    /// cooperative pool.
    private static func name(of address: LANAddress, interfaceIndex: UInt32) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: MulticastNames.name(
                        of: address, interfaceIndex: interfaceIndex, timeout: nameTimeout))
            }
        }
    }
}
