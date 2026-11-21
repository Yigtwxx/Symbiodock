import Testing
@testable import SymbiodockCore

struct LANAddressTests {
    @Test func anAddressReadsAndWritesDottedText() {
        let address = LANAddress("192.168.1.7")
        #expect(address?.value == 0xC0A8_0107)
        #expect(address?.text == "192.168.1.7")
        #expect(address?.bytes == [192, 168, 1, 7])
        #expect(address?.suffix == ".7")
        #expect(LANAddress(10, 0, 0, 254).text == "10.0.0.254")
    }

    @Test func textThatIsNotAnAddressIsRefused() {
        for text in ["", "192.168.1", "192.168.1.256", "192.168.1.7.1", "a.b.c.d", "192.168..7", "fe80::1"] {
            #expect(LANAddress(text) == nil)
        }
    }

    @Test func addressesSortByNumberNotByText() {
        let sorted = ["192.168.1.100", "192.168.1.9", "192.168.1.20"].compactMap(LANAddress.init).sorted()
        #expect(sorted.map(\.text) == ["192.168.1.9", "192.168.1.20", "192.168.1.100"])
    }

    @Test func aSweepCoversTheSubnetWithoutItsEndsAndThisMac() throws {
        let own = try #require(LANAddress("192.168.1.103"))
        let mask = try #require(LANAddress("255.255.255.0"))
        let hosts = SubnetSweep.hosts(own: own, mask: mask)
        #expect(hosts.count == 253)
        #expect(hosts.first?.text == "192.168.1.1")
        #expect(hosts.last?.text == "192.168.1.254")
        #expect(!hosts.contains(own))
    }

    @Test func aSweepStopsAtSlashTwentyTwo() throws {
        let own = try #require(LANAddress("10.4.1.20"))
        // /22: 1022 hosts, this Mac left out.
        #expect(SubnetSweep.hosts(own: own, mask: try #require(LANAddress("255.255.252.0"))).count == 1021)
        // /21 and wider are not swept: an office or a campus.
        #expect(SubnetSweep.hosts(own: own, mask: try #require(LANAddress("255.255.248.0"))).isEmpty)
        #expect(SubnetSweep.hosts(own: own, mask: try #require(LANAddress("255.0.0.0"))).isEmpty)
    }

    @Test func aSubnetWithNobodyElseIsNotSwept() throws {
        let own = try #require(LANAddress("192.168.1.1"))
        // /31 and /32: point-to-point links.
        #expect(SubnetSweep.hosts(own: own, mask: try #require(LANAddress("255.255.255.254"))).isEmpty)
        #expect(SubnetSweep.hosts(own: own, mask: try #require(LANAddress("255.255.255.255"))).isEmpty)
        // A mask with holes is not a mask.
        #expect(SubnetSweep.hosts(own: own, mask: try #require(LANAddress("255.0.255.0"))).isEmpty)
    }
}
