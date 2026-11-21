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

    private let store = SCDynamicStoreCreate(nil, "Symbiodock" as CFString, nil, nil)
    /// Names learned in scans, until the app quits. Never written anywhere.
    private var names: [LANAddress: String] = [:]
    /// Addresses already asked: a device that gave no name is not asked on every scan.
    private var asked: Set<LANAddress> = []

    /// The devices the Mac already knows. Nothing is sent.
    func known() -> Result {
        guard let route = LANReader.route(store: store) else { return Result(devices: [], canScan: false) }
        return Result(devices: devices(on: route), canScan: canScan(route))
    }

    /// Sweeps the subnet, then asks the devices that answered for their names.
    func scan() async -> Result {
        guard let route = LANReader.route(store: store) else { return Result(devices: [], canScan: false) }
        let hosts = SubnetSweep.hosts(own: route.own, mask: route.mask)
        guard !hosts.isEmpty else { return Result(devices: devices(on: route), canScan: false) }
        let outcome = LANSweeper.sweep(hosts)
        if outcome.isBlocked {
            return Result(devices: devices(on: route), canScan: true, isBlocked: true)
        }
        try? await Task.sleep(for: Self.settle)
        // Stopped meanwhile: nobody is asked for a name any more.
        guard !Task.isCancelled else { return Result(devices: devices(on: route), canScan: true) }
        let unnamed = devices(on: route).map(\.address).filter { !asked.contains($0) }.prefix(Self.nameLimit)
        asked.formUnion(unnamed)
        await withTaskGroup(of: (LANAddress, String?).self) { group in
            for address in unnamed {
                group.addTask { (address, await Self.name(of: address)) }
            }
            for await (address, host) in group {
                if let host, let name = LANNames.display(host) { names[address] = name }
            }
        }
        // A second look: slow devices have answered the sweep by now.
        return Result(devices: devices(on: route), canScan: true)
    }

    private func canScan(_ route: LANRoute) -> Bool {
        !SubnetSweep.hosts(own: route.own, mask: route.mask).isEmpty
    }

    private func devices(on route: LANRoute) -> [LANDevice] {
        let neighbours = NeighbourTable.neighbours(fromRouteDump: LANReader.neighbourDump())
            // The table also holds neighbours of other interfaces (a VPN, a second network).
            .filter { $0.address.value & route.mask.value == route.own.value & route.mask.value }
        return LANDevices.list(neighbours: neighbours, router: route.router, own: route.own, names: names)
    }

    /// The blocking query on a thread of its own, so the waits do not hold the actor or the
    /// cooperative pool.
    private static func name(of address: LANAddress) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: MulticastNames.name(of: address, timeout: nameTimeout))
            }
        }
    }
}
