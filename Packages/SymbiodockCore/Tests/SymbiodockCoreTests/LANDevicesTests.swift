import Testing
@testable import SymbiodockCore

struct LANDevicesTests {
    private let router = LANAddress(192, 168, 1, 1)
    private let own = LANAddress(192, 168, 1, 103)

    private func neighbour(_ last: UInt8, hardware: [UInt8]? = [2, 0, 0, 0, 0, 1]) -> LANNeighbour {
        LANNeighbour(address: LANAddress(192, 168, 1, last), hardware: hardware)
    }

    @Test func theListStartsWithTheRouterAndThisMac() {
        let devices = LANDevices.list(
            neighbours: [neighbour(107), neighbour(103), neighbour(100), neighbour(1), neighbour(102)],
            router: router, own: own,
            names: [LANAddress(192, 168, 1, 102): "Phone", LANAddress(192, 168, 1, 107): "alpha tv"])
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
    }

    @Test func theReverseQuestionSpellsTheAddressBackwards() {
        #expect(LANNames.reverseQuestion(for: LANAddress(192, 168, 1, 7)) == "7.1.168.192.in-addr.arpa")
    }

    @Test func aSweepIsBlockedWhenNearlyEverythingWasRefused() {
        // Recorded before the permission was given: 2 sent, 252 refused.
        #expect(SweepOutcome(sent: 2, refused: 252).isBlocked)
        #expect(SweepOutcome(sent: 0, refused: 253).isBlocked)
        #expect(!SweepOutcome(sent: 253, refused: 0).isBlocked)
        // A few refusals on a working network are not a missing permission.
        #expect(!SweepOutcome(sent: 240, refused: 13).isBlocked)
        #expect(!SweepOutcome(sent: 0, refused: 0).isBlocked)
    }

    @Test func theCountIsSpelledOut() {
        #expect(LANLabels.count(1) == "1 device")
        #expect(LANLabels.count(6) == "6 devices")
        #expect(LANLabels.count(0) == "0 devices")
    }
}
