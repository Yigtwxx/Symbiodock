import Testing
@testable import SymbiodockCore

struct LANDevicesTests {
    private let router = LANAddress(192, 168, 1, 1)
    private let own = LANAddress(192, 168, 1, 103)

    private func neighbour(_ last: UInt8, hardware: [UInt8]? = [2, 0, 0, 0, 0, 1]) -> LANNeighbour {
        LANNeighbour(address: LANAddress(192, 168, 1, last), hardware: hardware)
    }

    private let hardware: [UInt8] = [2, 0, 0, 0, 0, 1]

    private func identity(_ last: UInt8, hardware: [UInt8]? = nil) -> LANIdentity {
        LANIdentity(address: LANAddress(192, 168, 1, last), hardware: hardware ?? self.hardware)
    }

    @Test func theListStartsWithTheRouterAndThisMac() {
        let devices = LANDevices.list(
            neighbours: [neighbour(107), neighbour(103), neighbour(100), neighbour(1), neighbour(102)],
            router: router, own: own,
            names: [
                identity(102): "Phone", identity(107): "alpha tv",
            ])
        #expect(devices.map(\.title) == ["Router", "This Mac", "alpha tv", "Phone", "192.168.1.100"])
        #expect(devices.map(\.kind) == [.router, .thisMac, .other, .other, .other])
        #expect(devices.map(\.isNamed) == [true, true, true, true, false])
    }

    @Test func onlyEntriesWithAHardwareAddressAreDevices() {
        let devices = LANDevices.list(
            neighbours: [
                neighbour(1), neighbour(50, hardware: nil), neighbour(51, hardware: []),
                neighbour(255, hardware: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
                LANNeighbour(address: LANAddress(224, 0, 0, 251), hardware: [1, 0, 0x5E, 0, 0, 0xFB]),
                neighbour(52, hardware: [0, 0, 0, 0, 0, 0]),
            ],
            router: router, own: nil, names: [:])
        #expect(devices.map(\.title) == ["Router"])
    }

    @Test func thisMacIsListedEvenWhenTheTableDoesNotHoldIt() {
        let devices = LANDevices.list(neighbours: [neighbour(1)], router: router, own: own, names: [:])
        #expect(devices.map(\.title) == ["Router", "This Mac"])
        #expect(LANDevices.list(neighbours: [], router: nil, own: nil, names: [:]).isEmpty)
    }

    @Test func anAddressListedTwiceIsOneDevice() {
        let devices = LANDevices.list(
            neighbours: [neighbour(9), neighbour(9, hardware: [2, 0, 0, 0, 0, 7])], router: router, own: own,
            names: [:])
        #expect(devices.map(\.title) == ["This Mac", "192.168.1.9"])
    }

    @Test func unnamedDevicesFollowInAddressOrder() {
        let devices = LANDevices.list(
            neighbours: [neighbour(100), neighbour(9), neighbour(20)], router: nil, own: nil, names: [:])
        #expect(devices.map(\.title) == ["192.168.1.9", "192.168.1.20", "192.168.1.100"])
    }

    @Test func aHostNameBecomesWhatAPersonWouldCallTheDevice() {
        #expect(LANNames.display("Living-Room-TV.local.") == "Living Room TV")
        #expect(LANNames.display("phone.lan") == "phone")
        #expect(LANNames.display("printer") == "printer")
        #expect(LANNames.display("a--b_c.home.arpa") == "a b_c")
        #expect(LANNames.display("") == nil)
        #expect(LANNames.display(".local") == nil)
        #expect(LANNames.display("---.local") == nil)
    }

    @Test func aNameOnTheWireIsLengthPrefixedLabels() {
        let wire: [UInt8] = [5] + Array("phone".utf8) + [5] + Array("local".utf8) + [0]
        #expect(LANNames.host(fromWire: wire) == "phone.local")
        #expect(LANNames.host(fromWire: [0]) == nil)
        #expect(LANNames.host(fromWire: []) == nil)
        // A label that runs past the end, and a compression pointer, are not read.
        #expect(LANNames.host(fromWire: [9, 0x61, 0x62]) == nil)
        #expect(LANNames.host(fromWire: [0xC0, 0x0C]) == nil)
        // Cut off before its closing zero.
        #expect(LANNames.host(fromWire: [5] + Array("phone".utf8)) == nil)
    }

    /// The name comes from another device: it cannot break a line, turn the text around or
    /// fill the row.
    @Test func aNameFromTheNetworkIsMadeHarmless() {
        #expect(LANNames.display("TV\u{202E}evil\nline\u{0}\u{200B}.local") == "TVevilline")
        #expect(LANNames.display("\u{202E}\u{200F}.local") == nil)
        let long = String(repeating: "a", count: 63)
        #expect(LANNames.display(long + ".local")?.count == 40)
        #expect(LANNames.display("Zoë's-Büro.local") == "Zoë's Büro")
    }

    @Test func theReverseQuestionSpellsTheAddressBackwards() {
        #expect(LANNames.reverseQuestion(for: LANAddress(192, 168, 1, 7)) == "7.1.168.192.in-addr.arpa")
    }

    @Test func aNameBelongsToAnAddressAndAHardwareAddress() {
        let names = [identity(102): "Phone"]
        let same = LANDevices.list(neighbours: [neighbour(102)], router: nil, own: nil, names: names)
        #expect(same.map(\.title) == ["Phone"])
        // Another network with the same subnet: a stranger's device at the same address.
        let other = LANDevices.list(
            neighbours: [neighbour(102, hardware: [2, 0, 0, 0, 0, 9])], router: nil, own: nil, names: names)
        #expect(other.map(\.title) == ["192.168.1.102"])
    }

    @Test func devicesAmongNeighboursAreTheOnesTheListShows() {
        let devices = LANDevices.devices(among: [
            neighbour(5), neighbour(50, hardware: nil), neighbour(5, hardware: [2, 0, 0, 0, 0, 7]),
            neighbour(255, hardware: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]), neighbour(6),
        ])
        #expect(devices == [neighbour(5), neighbour(6)])
    }

    private func address(_ last: UInt8) -> LANAddress { LANAddress(192, 168, 1, last) }

    @Test func aSweepIsBlockedWhenAKnownDeviceWasRefused() {
        let outcome = SweepOutcome(sent: 3, refused: [address(20), address(21), address(50)])
        #expect(outcome.isBlocked(witnesses: [address(20), address(21)]))
        // One is enough: the kernel never refuses a device it holds an address for.
        #expect(outcome.isBlocked(witnesses: [address(20), address(22)]))
        // None of the known devices was refused: the permission is there.
        #expect(!outcome.isBlocked(witnesses: [address(22), address(23)]))
    }

    /// The kernel itself refuses addresses that did not answer for a while.
    @Test func repeatedScansOfASilentRangeAreNotBlocked() {
        let outcome = SweepOutcome(sent: 6, refused: Set((2...248).map(address)))
        #expect(!outcome.isBlocked(witnesses: [address(1)]))
    }

    @Test func withoutWitnessesNineInTenRefusalsAreBlocked() {
        let refused = Set((2...253).map(address))
        #expect(SweepOutcome(sent: 2, refused: refused).isBlocked(witnesses: []))
        #expect(!SweepOutcome(sent: 253, refused: []).isBlocked(witnesses: []))
        // A few refusals on a working network are not a missing permission.
        #expect(!SweepOutcome(sent: 240, refused: Set((2...14).map(address))).isBlocked(witnesses: []))
        #expect(!SweepOutcome(sent: 0, refused: []).isBlocked(witnesses: []))
    }

    @Test func aNetworkCanBeScannedOnlyWhenItsRouterAnswersArp() {
        let mask = LANAddress(255, 255, 255, 0)
        func can(_ neighbours: [LANNeighbour], router: LANAddress? = LANAddress(192, 168, 1, 1)) -> Bool {
            LANDevices.canScan(neighbours: neighbours, router: router, own: own, mask: mask)
        }
        #expect(can([neighbour(1)]))
        // A tunnel: a router address, but nobody with a hardware address behind it.
        #expect(!can([]))
        #expect(!can([neighbour(1, hardware: nil)]))
        #expect(!can([neighbour(7)]))
        #expect(!can([neighbour(1)], router: nil))
        // A router outside the subnet is not the local network's.
        #expect(!can([LANNeighbour(address: LANAddress(10, 0, 0, 1), hardware: hardware)],
                     router: LANAddress(10, 0, 0, 1)))
        // Too wide a subnet is not swept.
        #expect(!LANDevices.canScan(
            neighbours: [neighbour(1)], router: router, own: own, mask: LANAddress(255, 0, 0, 0)))
    }

    @Test func theCountIsSpelledOut() {
        #expect(LANLabels.count(1) == "1 device")
        #expect(LANLabels.count(6) == "6 devices")
        #expect(LANLabels.count(0) == "0 devices")
    }
}
