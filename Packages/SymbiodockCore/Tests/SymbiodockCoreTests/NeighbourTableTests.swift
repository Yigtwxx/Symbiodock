import Testing
@testable import SymbiodockCore

struct NeighbourTableTests {
    /// One message of `sysctl` `NET_RT_FLAGS` + `RTF_LLINFO` as macOS 27.0.1 on Apple silicon
    /// returns it, recorded 2026-11-21: the router's entry. The hardware address is replaced
    /// with 02:00:00:00:00:01.
    private static let routerMessage =
        "900005040e0000000504021523000000000000000000000000000000cb0700000000000000000000dc050000"
        + "000000005b70016b0000000000000000000000000000000000000000cb070000b40500000000000000000000"
        + "0000000010020000c0a80101000000000000000014120e000600060002000000000100000000000010020000"
        + "c0a801670000000000000000"

    private func bytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return bytes
    }

    /// A message with the same layout for another address: the header, an IPv4 address and a
    /// link-layer address with or without hardware bytes.
    private func message(_ address: LANAddress, hardware: [UInt8]?) -> [UInt8] {
        var message = [UInt8](repeating: 0, count: NeighbourTable.headerSize)
        var inet = [UInt8](repeating: 0, count: 16)
        inet[0] = 16
        inet[1] = 2
        inet.replaceSubrange(4..<8, with: address.bytes)
        var link = [UInt8](repeating: 0, count: 20)
        link[0] = 20
        link[1] = 18
        link[2] = 14
        link[4] = 6
        if let hardware {
            link[6] = UInt8(hardware.count)
            link.replaceSubrange(8..<(8 + hardware.count), with: hardware)
        }
        message += inet + link
        message[0] = UInt8(message.count & 0xFF)
        message[1] = UInt8(message.count >> 8)
        return message
    }

    @Test func theRecordedMessageIsTheRouter() {
        let dump = bytes(Self.routerMessage)
        #expect(dump.count == 144)
        #expect(NeighbourTable.neighbours(fromRouteDump: dump) == [
            LANNeighbour(address: LANAddress(192, 168, 1, 1), hardware: [0x02, 0, 0, 0, 0, 0x01])
        ])
    }

    @Test func messagesFollowEachOther() {
        let phone = LANAddress(192, 168, 1, 100)
        let silent = LANAddress(192, 168, 1, 55)
        let dump = bytes(Self.routerMessage) + message(phone, hardware: [0x4A, 1, 2, 3, 4, 5])
            + message(silent, hardware: nil)
        let neighbours = NeighbourTable.neighbours(fromRouteDump: dump)
        #expect(neighbours.map(\.address.text) == ["192.168.1.1", "192.168.1.100", "192.168.1.55"])
        #expect(neighbours[1].hardware == [0x4A, 1, 2, 3, 4, 5])
        // Nobody answered for this address: the kernel holds the entry without an address.
        #expect(neighbours[2].hardware == nil)
    }

    @Test func aDumpCutShortGivesWhatCameBeforeTheCut() {
        let whole = bytes(Self.routerMessage)
        #expect(NeighbourTable.neighbours(fromRouteDump: []).isEmpty)
        #expect(NeighbourTable.neighbours(fromRouteDump: Array(whole.prefix(60))).isEmpty)
        #expect(NeighbourTable.neighbours(fromRouteDump: whole + Array(whole.prefix(100))).count == 1)
    }

    @Test func aMessageThatLiesAboutItsLengthEndsTheWalk() {
        var broken = bytes(Self.routerMessage)
        broken[0] = 0
        broken[1] = 0
        #expect(NeighbourTable.neighbours(fromRouteDump: broken).isEmpty)
        var tooLong = bytes(Self.routerMessage)
        tooLong[0] = 0xFF
        tooLong[1] = 0xFF
        #expect(NeighbourTable.neighbours(fromRouteDump: tooLong).isEmpty)
    }

    @Test func anEntryOfAnotherFamilyIsSkipped() {
        var other = message(LANAddress(192, 168, 1, 9), hardware: [2, 0, 0, 0, 0, 9])
        other[NeighbourTable.headerSize + 1] = 30
        let dump = other + bytes(Self.routerMessage)
        #expect(NeighbourTable.neighbours(fromRouteDump: dump).map(\.address.text) == ["192.168.1.1"])
    }
}
