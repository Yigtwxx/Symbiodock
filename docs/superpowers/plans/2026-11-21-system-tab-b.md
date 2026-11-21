# System Tab, Part B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The System tab's `Devices` panel lists the devices on the network: what the Mac already knows without sending anything, and, when the owner presses `Scan`, everything a sweep of the subnet finds, with the names the devices give.

**Architecture:** Pure logic in `Packages/SymbiodockCore` (addresses, the neighbour table's bytes, which entries are devices, names, the sweep's addresses, what a sweep's outcome means), tested with `swift test`. The app target reads the table and the route, sends the sweep and asks for names inside one actor, `LANScanner`. `SystemCoordinator` reads the known devices while the tab is shown and runs a scan when `IslandState` says one was asked for; the view only calls `state.requestLANScan()`.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Darwin sockets and `sysctl`, `dnssd`, SystemConfiguration, Swift Testing, XcodeGen.

Spec: `docs/superpowers/specs/2026-11-21-system-tab-design.md` ("Ağdaki cihazlar", "İzin", "Devices paneli", "Doğrulanmamış varsayımlar"). Part A (`docs/superpowers/plans/2026-11-21-system-tab-a.md`) is done and in `main`.

## What the probe showed (2026-11-21, inside the app, the owner pressed Allow)

- The app, started through LaunchServices, reads the neighbour table (`sysctl` `NET_RT_FLAGS` + `RTF_LLINFO`, `AF_INET`) without the Local Network permission and without sending anything: 5 entries with a hardware address (the router, three devices and this Mac itself). The same call from a binary started in a terminal returns nothing: **run every check of this plan through `open`, never by starting the binary directly.**
- One empty UDP datagram to port 9 of each of the 254 addresses: before the permission 252 of them failed with `EHOSTUNREACH` (65) and macOS asked; after Allow all were sent. The table then held 254 entries, but only the 6 that answered had a hardware address.
- The router's reverse DNS named nothing. A multicast DNS reverse query named 2 of 6 (an iPhone and this Mac) within 0.2 s; the others did not answer in 2 s.
- `/usr/sbin/arp` run from the app printed nothing: it is not used.
- The code that did this is `Symbiodock/System/LANProbe.swift` (Debug only). Its sweep, table parsing and name query worked as written; Task 3 moves them into their places and deletes the probe.

## Global Constraints

- Minimum macOS 14.0. Swift 6 strict concurrency, no extra flags.
- **Nothing is sent to the network by itself.** The sweep and the name queries run only after `Scan` was pressed. Showing the tab only reads what the Mac already knows.
- No scan when the subnet is wider than /22 (more than 1022 host addresses), or without a network: then there is no `Scan` button.
- One scan at a time. While it runs the button reads `Scanning…` and cannot be pressed.
- A device is a neighbour entry with a hardware address that is not broadcast or multicast. The router is `Router`, this Mac is `This Mac`; a device without a name shows its address.
- Device names, addresses and hardware addresses are never logged, never written to disk, never printed by a hook. Logs and hooks carry counts and booleans only (`Logger(subsystem: "com.yigtwxx.Symbiodock", category: "system")`).
- `SymbiodockCore` imports only Foundation. No AppKit, SwiftUI, IOKit or `dnssd` there.
- No view may redraw frame by frame at rest. The list changes only when a new list arrives.
- No hook, no `sudo`, no new third-party dependency, no helper process.
- Interface text is English: `DEVICES`, `Scan`, `Scanning…`, `Router`, `This Mac`, `Local Network access needed`, `6 devices` / `1 device`.
- The permission text (already in `project.yml` and `Info.plist`): "Symbiodock looks for the devices on your network to count them and show their names in the System tab."
- Plans are written without compiling the app. If code here does not compile, fix it while keeping the behaviour and the interfaces, and correct this plan in the same commit.
- Verification after every task:
  - `swift test --package-path Packages/SymbiodockCore` passes (802 tests before this plan).
  - `xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3` ends with `** BUILD SUCCEEDED **`.
- Do not press, script or trigger `Scan` in the running app, and do not run anything that sweeps the network: only the owner scans. Checks in this plan read counts through hooks that send nothing.
- Commits: Conventional Commits, title at most 72 characters, imperative, body says why. Commit each task and push to `main` (`git push origin main`). End every commit message with:

```
Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01BW1DAFBBz2zwgt57hNkzQK
```

## File Structure

| File | Responsibility |
|---|---|
| `Packages/SymbiodockCore/Sources/SymbiodockCore/System/LANAddress.swift` (create) | An IPv4 address; the addresses of a subnet to sweep |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/System/NeighbourTable.swift` (create) | The kernel's neighbour table, from its bytes |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/System/LANDevices.swift` (create) | Which neighbours are devices, their titles and order; names; what a sweep's outcome means |
| `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift` (modify) | `lanDevices`, `canScanLAN`, `lanScan`, `requestLANScan()` |
| `Symbiodock/System/LANReader.swift` (create) | The route and the table's bytes |
| `Symbiodock/System/LANSweeper.swift` (create) | The sweep |
| `Symbiodock/System/MulticastNames.swift` (create) | One name query |
| `Symbiodock/System/LANScanner.swift` (create) | The actor: known devices, a scan |
| `Symbiodock/System/SystemCoordinator.swift` (modify) | Reads the known devices while shown; runs a requested scan |
| `Symbiodock/System/LANProbe.swift` (delete) | The probe is over |
| `Symbiodock/App/AppDelegate.swift`, `IslandMenu.swift` (modify) | Wiring; the `Local Network access needed` item |
| `Symbiodock/Island/System/SystemContent.swift`, `Symbiodock/Island/ExpandedIsland.swift` (modify) | The list, the button, the note, the header summary |
| `Symbiodock/System/DemoSystem.swift`, `Symbiodock/App/DebugRender.swift` (modify) | Demo devices, renders |
| `CLAUDE.md`, the spec (modify) | Status |

---

### Task 1: Addresses, the table, the devices

**Files:**
- Create: `Packages/SymbiodockCore/Sources/SymbiodockCore/System/LANAddress.swift`, `NeighbourTable.swift`, `LANDevices.swift`
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/LANAddressTests.swift`, `NeighbourTableTests.swift`, `LANDevicesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `LANAddress`: `init(value: UInt32)`, `init?(_ text: String)`, `init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8)`, `value: UInt32` (host order), `bytes: [UInt8]`, `text: String`, `suffix: String` (".7"); `Hashable`, `Comparable`, `Sendable`.
  - `SubnetSweep.maximumHosts` (1022), `SubnetSweep.hosts(own:mask:) -> [LANAddress]`.
  - `LANNeighbour(address:hardware:)` — `hardware: [UInt8]?`.
  - `NeighbourTable.headerSize`, `NeighbourTable.neighbours(fromRouteDump: [UInt8]) -> [LANNeighbour]`.
  - `LANDevice(address:name:kind:)` with `Kind { router, thisMac, other }`, `id`, `title`, `isNamed`.
  - `LANDevices.list(neighbours:router:own:names:) -> [LANDevice]`.
  - `LANNames.display(_ host: String) -> String?`, `LANNames.host(fromWire: [UInt8]) -> String?`, `LANNames.reverseQuestion(for: LANAddress) -> String`.
  - `SweepOutcome(sent:refused:)` with `isBlocked`.
  - `LANLabels.count(_ devices: Int) -> String`.

- [x] **Step 1: Write the failing tests**

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/LANAddressTests.swift`:

```swift
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
```

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/NeighbourTableTests.swift`:

```swift
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
```

`Packages/SymbiodockCore/Tests/SymbiodockCoreTests/LANDevicesTests.swift`:

```swift
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
```

- [x] **Step 2: Run the tests and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -15`
Expected: the build fails with `cannot find 'LANAddress' in scope`.

- [x] **Step 3: Write the code**

`Packages/SymbiodockCore/Sources/SymbiodockCore/System/LANAddress.swift`:

```swift
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
```

`Packages/SymbiodockCore/Sources/SymbiodockCore/System/NeighbourTable.swift`:

```swift
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
```

`Packages/SymbiodockCore/Sources/SymbiodockCore/System/LANDevices.swift`:

```swift
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
```

- [x] **Step 4: Run the tests and see them pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: all tests pass (802 + 21 = 823).

After the review two things were hardened in `LANNames` (see the file; this plan's listing above is the first version): a wire name cut off before its closing zero is refused, and `display` drops control and format characters and caps the name at 40 characters, because the name comes from another device. One test was added: 824.

- [x] **Step 5: Commit**

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): read the neighbour table into a list of devices" -m "Which entries are devices, how they are named and ordered, which addresses a scan may reach and when a sweep was kept back are decided here, away from the sockets, so they are tested."
git push origin main
```

---

### Task 2: What the island knows about the network

**Files:**
- Modify: `Packages/SymbiodockCore/Sources/SymbiodockCore/IslandState.swift` (properties after `networkHistory`; methods after `setSystem(_:history:)`)
- Test: `Packages/SymbiodockCore/Tests/SymbiodockCoreTests/IslandStateTests.swift`

**Interfaces:**
- Consumes: `LANDevice` (Task 1).
- Produces: `LANScanState { idle, scanning, blocked }`; `IslandState.lanDevices: [LANDevice]`, `.canScanLAN: Bool`, `.lanScan: LANScanState`, `.setLANDevices(_:canScan:)`, `.requestLANScan()`, `.finishLANScan(blocked:)`.

- [x] **Step 1: Write the failing tests**

Add to `IslandStateTests.swift`, at the end of the struct:

```swift
    private func device(_ last: UInt8) -> LANDevice {
        LANDevice(address: LANAddress(192, 168, 1, last), name: nil, kind: .other)
    }

    @Test func theKnownDevicesAreKept() {
        let state = IslandState()
        #expect(state.lanDevices.isEmpty)
        #expect(!state.canScanLAN)
        #expect(state.lanScan == .idle)
        state.setLANDevices([device(1), device(9)], canScan: true)
        #expect(state.lanDevices == [device(1), device(9)])
        #expect(state.canScanLAN)
    }

    @Test func aScanIsAskedForOnlyWhereOneCanRun() {
        let state = IslandState()
        state.requestLANScan()
        // No network, or one too wide to sweep.
        #expect(state.lanScan == .idle)
        state.setLANDevices([device(1)], canScan: true)
        state.requestLANScan()
        #expect(state.lanScan == .scanning)
    }

    @Test func aScanEndsIdleOrBlocked() {
        let state = IslandState()
        state.setLANDevices([], canScan: true)
        state.requestLANScan()
        state.finishLANScan(blocked: false)
        #expect(state.lanScan == .idle)
        state.requestLANScan()
        state.finishLANScan(blocked: true)
        #expect(state.lanScan == .blocked)
        // The permission may have been given since: pressing again tries again.
        state.requestLANScan()
        #expect(state.lanScan == .scanning)
    }

    @Test func aScanThatWasNotRunningCannotEnd() {
        let state = IslandState()
        state.finishLANScan(blocked: true)
        #expect(state.lanScan == .idle)
    }

    @Test func losingTheNetworkEndsTheBlockedNote() {
        let state = IslandState()
        state.setLANDevices([device(1)], canScan: true)
        state.requestLANScan()
        state.finishLANScan(blocked: true)
        state.setLANDevices([], canScan: false)
        // Nothing to scan: the note about the permission would point at nothing.
        #expect(state.lanScan == .idle)
    }
```

- [x] **Step 2: Run the tests and see them fail**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -15`
Expected: the build fails with `value of type 'IslandState' has no member 'lanDevices'`.

- [x] **Step 3: Write the code**

In `Packages/SymbiodockCore/Sources/SymbiodockCore/System/LANDevices.swift`, add at the end:

```swift

/// Where a scan of the network stands.
public enum LANScanState: Equatable, Sendable {
    case idle
    /// Asked for and not finished.
    case scanning
    /// The last scan was kept back by macOS: the Local Network permission is missing.
    case blocked
}
```

In `IslandState.swift`, after the `networkHistory` property:

```swift
    /// The devices on the network, as far as they are known: what the Mac has already talked
    /// to, and after a scan everything that answered.
    public private(set) var lanDevices: [LANDevice] = []
    /// Whether there is a network narrow enough to scan.
    public private(set) var canScanLAN = false
    /// Where a scan stands. The app runs one when this turns to `.scanning`.
    public private(set) var lanScan: LANScanState = .idle
```

After `setSystem(_:history:)`:

```swift

    /// The devices known now, and whether a scan could run on this network.
    public func setLANDevices(_ devices: [LANDevice], canScan: Bool) {
        // Assign only on change: every assignment redraws the island.
        if lanDevices != devices { lanDevices = devices }
        if canScanLAN != canScan { canScanLAN = canScan }
        // Without a network to scan, the note about the permission points at nothing.
        if !canScan, lanScan == .blocked { lanScan = .idle }
    }

    /// `Scan` was pressed. Ignored while a scan runs and where none can.
    public func requestLANScan() {
        guard canScanLAN, lanScan != .scanning else { return }
        lanScan = .scanning
    }

    /// The scan that was asked for has ended.
    public func finishLANScan(blocked: Bool) {
        guard lanScan == .scanning else { return }
        lanScan = blocked ? .blocked : .idle
    }
```

- [x] **Step 4: Run the tests and see them pass**

Run: `swift test --package-path Packages/SymbiodockCore 2>&1 | tail -5`
Expected: all tests pass (824 + 5 = 829).

- [x] **Step 5: Build the app and commit**

Run the `xcodebuild` line from Global Constraints. Expected: `** BUILD SUCCEEDED **`.

```bash
git add Packages/SymbiodockCore
git commit -m "feat(core): keep the known devices and the scan's state" -m "The view only says that Scan was pressed; the state decides whether a scan may start, so two cannot run and none starts where there is nothing to scan."
git push origin main
```

---

### Task 3: Reading, sweeping, naming

**Files:**
- Create: `Symbiodock/System/LANReader.swift`, `LANSweeper.swift`, `MulticastNames.swift`, `LANScanner.swift`
- Modify: `Symbiodock/System/SystemCoordinator.swift`, `Symbiodock/System/DemoSystem.swift` (the hook), `Symbiodock/App/AppDelegate.swift`, `Symbiodock/App/IslandMenu.swift`
- Delete: `Symbiodock/System/LANProbe.swift`

**Interfaces:**
- Consumes: Task 1 and 2; `SystemCoordinator` as Part A left it (`init(isWatching:onUpdate:)`, `observe()`, `refresh()`, `loop()`).
- Produces:
  - `LANRoute { router: LANAddress?, own: LANAddress, mask: LANAddress }`; `LANReader.route(store: SCDynamicStore?) -> LANRoute?`; `LANReader.neighbourDump() -> [UInt8]`
  - `LANSweeper.sweep(_ hosts: [LANAddress]) -> SweepOutcome`
  - `MulticastNames.name(of: LANAddress, timeout: TimeInterval) -> String?` (blocking)
  - `actor LANScanner`: `known() -> LANScanner.Result`, `scan() async -> LANScanner.Result`; `Result { devices: [LANDevice], canScan: Bool, isBlocked: Bool }`
  - `SystemCoordinator(isWatching:isScanRequested:onUpdate:onDevices:onScanEnd:)`
  - `IslandMenu.setLocalNetworkAccessNeeded(_ needed: Bool)`

- [x] **Step 1: The route and the table**

`Symbiodock/System/LANReader.swift`:

```swift
import Darwin
import Foundation
import SymbiodockCore
import SystemConfiguration

/// Where this Mac is on its network.
struct LANRoute: Equatable, Sendable {
    var router: LANAddress?
    var own: LANAddress
    var mask: LANAddress
}

/// Reads what the system already knows about the network. Nothing is sent, and no
/// permission is needed: macOS gives an app its neighbour table as it stands.
enum LANReader {
    /// The primary interface's address, mask and router; nil without a network.
    static func route(store: SCDynamicStore?) -> LANRoute? {
        guard let store,
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any],
              let interface = global["PrimaryInterface"] as? String,
              let own = SCDynamicStoreCopyValue(
                  store, "State:/Network/Interface/\(interface)/IPv4" as CFString) as? [String: Any],
              let address = (own["Addresses"] as? [String])?.first.flatMap(LANAddress.init),
              let mask = (own["SubnetMasks"] as? [String])?.first.flatMap(LANAddress.init)
        else { return nil }
        return LANRoute(
            router: (global["Router"] as? String).flatMap(LANAddress.init), own: address, mask: mask)
    }

    /// The IPv4 neighbour table's bytes; empty when it cannot be read.
    static func neighbourDump() -> [UInt8] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
        // Room to spare: the table may grow between the two calls.
        length += 4096
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [] }
        return Array(buffer.prefix(length))
    }
}
```

- [x] **Step 2: The sweep**

`Symbiodock/System/LANSweeper.swift`:

```swift
import Darwin
import Foundation
import SymbiodockCore

/// Sends one empty UDP datagram to each address, so that the kernel asks who has it; those
/// that answer get a hardware address in the neighbour table. The first time, this is what
/// makes macOS ask for the Local Network permission. Only ever called for a scan the owner
/// asked for.
enum LANSweeper {
    /// The discard port: nothing answers it, and nothing needs to.
    private static let port: UInt16 = 9

    static func sweep(_ hosts: [LANAddress]) -> SweepOutcome {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return SweepOutcome(sent: 0, refused: 0) }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        var outcome = SweepOutcome(sent: 0, refused: 0)
        for host in hosts {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            target.sin_port = port.bigEndian
            target.sin_addr.s_addr = host.value.bigEndian
            let result = withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, nil, 0, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result >= 0 {
                outcome.sent += 1
            } else if errno == EHOSTUNREACH {
                outcome.refused += 1
            }
        }
        return outcome
    }
}
```

- [x] **Step 3: One name**

`Symbiodock/System/MulticastNames.swift`:

```swift
import Darwin
import Foundation
import SymbiodockCore
import dnssd

/// Asks a device for its own name over multicast DNS (a reverse query). Apple devices and
/// many others answer within a fraction of a second; the rest never do. Only ever called
/// for a scan the owner asked for.
enum MulticastNames {
    private final class Answer {
        var host: String?
    }

    /// Blocks for at most `timeout`. The host name as the device gave it, such as
    /// "Living-Room-TV.local"; nil when it did not answer.
    static func name(of address: LANAddress, timeout: TimeInterval) -> String? {
        let answer = Answer()
        var reference: DNSServiceRef?
        let callback: DNSServiceQueryRecordReply = { _, _, _, error, _, _, _, length, data, _, context in
            guard error == kDNSServiceErr_NoError, let data, let context, length > 0 else { return }
            let bytes = Array(UnsafeRawBufferPointer(start: data, count: Int(length)))
            Unmanaged<Answer>.fromOpaque(context).takeUnretainedValue().host = LANNames.host(fromWire: bytes)
        }
        let status = DNSServiceQueryRecord(
            &reference, kDNSServiceFlagsForceMulticast, 0, LANNames.reverseQuestion(for: address),
            UInt16(kDNSServiceType_PTR), UInt16(kDNSServiceClass_IN), callback,
            Unmanaged.passUnretained(answer).toOpaque())
        guard status == kDNSServiceErr_NoError, let reference else { return nil }
        defer { DNSServiceRefDeallocate(reference) }
        let descriptor = DNSServiceRefSockFD(reference)
        let deadline = Date().addingTimeInterval(timeout)
        while answer.host == nil, Date() < deadline {
            var readable = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            // `answer` outlives the loop: the callback runs only inside the call below.
            if poll(&readable, 1, 200) > 0, DNSServiceProcessResult(reference) != kDNSServiceErr_NoError { break }
        }
        return answer.host
    }
}
```

- [x] **Step 4: The scanner**

`Symbiodock/System/LANScanner.swift`:

```swift
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
```

- [x] **Step 5: The coordinator reads the devices and runs a scan**

In `Symbiodock/System/SystemCoordinator.swift`:

- Change the type's doc comment to:

```swift
/// Measures this Mac while the System tab is on screen, and only then: every two seconds,
/// off the main thread, and hands each snapshot to the app. While the tab is shown it also
/// reads the devices the Mac already knows, and it runs a scan of the network when one was
/// asked for. Nothing is sent to the network unless a scan was asked for.
```

- After `temperatureEvery`, add:

```swift
    /// The known devices are read with every fifth reading: every ten seconds.
    private static let devicesEvery = 5
```

- Replace the stored closures, the `reader` and the initialiser with:

```swift
    private let isWatching: @MainActor () -> Bool
    private let isScanRequested: @MainActor () -> Bool
    private let onUpdate: @MainActor (SystemSnapshot, NetworkHistory) -> Void
    private let onDevices: @MainActor ([LANDevice], Bool) -> Void
    private let onScanEnd: @MainActor (Bool) -> Void
    private let reader = SystemReader()
    private let scanner = LANScanner()
    private var meter = SystemMeter()
    private var task: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    /// Tells the running loop from one that has been replaced.
    private var run = 0
    private var isStopped = true
    private var hasLogged = false

    /// - Parameter isWatching: whether the open island shows the System tab.
    /// - Parameter isScanRequested: whether a scan was asked for and has not ended.
    ///   Both must read observable state: the coordinator observes what they read.
    /// - Parameter onDevices: the devices known now, and whether this network can be scanned.
    /// - Parameter onScanEnd: the scan has ended; true when macOS kept it back.
    init(
        isWatching: @escaping @MainActor () -> Bool,
        isScanRequested: @escaping @MainActor () -> Bool,
        onUpdate: @escaping @MainActor (SystemSnapshot, NetworkHistory) -> Void,
        onDevices: @escaping @MainActor ([LANDevice], Bool) -> Void,
        onScanEnd: @escaping @MainActor (Bool) -> Void
    ) {
        self.isWatching = isWatching
        self.isScanRequested = isScanRequested
        self.onUpdate = onUpdate
        self.onDevices = onDevices
        self.onScanEnd = onScanEnd
    }
```

(Remove the old properties and initialiser these replace; `task`, `run`, `isStopped`, `hasLogged`, `meter` and `reader` must each be declared once.)

- In `stop()`, also cancel a scan:

```swift
    func stop() {
        isStopped = true
        endLoop()
        // The task clears `scanTask` itself when it ends, so a scan asked for after a restart
        // cannot overlap one that is still winding down.
        scanTask?.cancel()
    }
```

- In `observe()`, read both closures inside the tracking block:

```swift
        withObservationTracking {
            _ = isWatching()
            _ = isScanRequested()
        } onChange: { [weak self] in
```

- Replace `refresh()`:

```swift
    private func refresh() {
        if isWatching() { beginLoop() } else { endLoop() }
        if isScanRequested() { beginScan() }
    }

    /// Runs the scan that was asked for. It is short, and it finishes even if the tab is left
    /// meanwhile: the state waits for its end.
    private func beginScan() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            guard let scanner = self?.scanner else { return }
            let result = await scanner.scan()
            guard let self else { return }
            // The end is always reported, also for a scan the coordinator was stopped during:
            // the state waits for it, and the button with it.
            self.onDevices(result.devices, result.canScan)
            self.onScanEnd(result.isBlocked)
            Self.log.notice(
                "scan: \(result.devices.count, privacy: .public) devices, blocked \(result.isBlocked, privacy: .public)")
            self.scanTask = nil
        }
    }
```

- In `loop()`, read the known devices on the first pass and every fifth after it. Add at the top of the `while` body, before the system reading:

```swift
            if count % Self.devicesEvery == 0, scanTask == nil {
                let known = await scanner.known()
                guard !Task.isCancelled else { return }
                // A scan that began meanwhile brings a fuller list itself.
                if scanTask == nil { onDevices(known.devices, known.canScan) }
            }
```

- [x] **Step 6: The menu item**

In `Symbiodock/App/IslandMenu.swift`:

- Beside `musicAccessItem`, add a property:

```swift
    private let localNetworkItem: NSMenuItem
```

- In `init()`, before `super.init()`:

```swift
        localNetworkItem = NSMenuItem(
            title: "Local Network access needed", action: #selector(openLocalNetworkSettings), keyEquivalent: "")
```

- Where `musicAccessItem` is added to the menu, add the new item above it, so that both share the separator:

```swift
        localNetworkItem.target = self
        menu.addItem(localNetworkItem)
        musicAccessItem.target = self
        menu.addItem(musicAccessItem)
        menu.addItem(musicAccessSeparator)
```

- Replace `setMusicAccessNeeded` and add its sibling; the separator shows while either item does. In `init()`, the existing call `setMusicAccessNeeded(false)` stays; add `setLocalNetworkAccessNeeded(false)` after it.

```swift
    /// Shows the entry only while Automation consent for Music is missing.
    func setMusicAccessNeeded(_ needed: Bool) {
        musicAccessItem.isHidden = !needed
        musicAccessSeparator.isHidden = musicAccessItem.isHidden && localNetworkItem.isHidden
    }

    /// Shows the entry only while a scan was kept back for want of the Local Network permission.
    func setLocalNetworkAccessNeeded(_ needed: Bool) {
        localNetworkItem.isHidden = !needed
        musicAccessSeparator.isHidden = musicAccessItem.isHidden && localNetworkItem.isHidden
    }
```

- Beside `openAutomationSettings`:

```swift
    @objc private func openLocalNetworkSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
        else { return }
        NSWorkspace.shared.open(url)
    }
```

- [x] **Step 7: Wire it, and remove the probe**

Delete `Symbiodock/System/LANProbe.swift`.

In `Symbiodock/App/AppDelegate.swift`:

- The debug hooks line goes back to:

```swift
        if ConvertHook.runIfRequested() || FlowHook.runIfRequested() || SystemHook.runIfRequested() { return }
```

- Replace `startSystem()`:

```swift
    /// Starts measuring this Mac whenever the open island shows the System tab, and scanning
    /// the network whenever a scan was asked for.
    private func startSystem() {
        let system = SystemCoordinator(
            isWatching: { [weak self] in
                self.map { $0.state.phase == .expanded && $0.state.selectedTab == .system } ?? false
            },
            isScanRequested: { [weak self] in self?.state.lanScan == .scanning },
            onUpdate: { [weak self] snapshot, history in
                self?.state.setSystem(snapshot, history: history)
            },
            onDevices: { [weak self] devices, canScan in
                self?.state.setLANDevices(devices, canScan: canScan)
            },
            onScanEnd: { [weak self] blocked in
                self?.state.finishLANScan(blocked: blocked)
                self?.islandMenu?.setLocalNetworkAccessNeeded(blocked)
            })
        system.start()
        self.system = system
    }
```

In `Symbiodock/System/DemoSystem.swift`, `SystemHook`:

- `checkLoop()` builds a `SystemCoordinator`: give it the new parameters, and count the device lists too. Replace the coordinator's construction with:

```swift
            let lists = Tally()
            let coordinator = SystemCoordinator(
                isWatching: { state.phase == .expanded && state.selectedTab == .system },
                isScanRequested: { state.lanScan == .scanning },
                onUpdate: { snapshot, history in
                    tally.count += 1
                    state.setSystem(snapshot, history: history)
                },
                onDevices: { devices, canScan in
                    lists.count += 1
                    state.setLANDevices(devices, canScan: canScan)
                },
                onScanEnd: { state.finishLANScan(blocked: $0) })
```

- and in `stretch`, print the devices' count, never the devices:

```swift
                print("\(name), \(seconds) s: \(tally.count - before) measures, cpu \(cpu), graph \(state.networkHistory.samples.count), \(lists.count) device lists, \(state.lanDevices.count) devices, can scan \(state.canScanLAN)")
```

The hook never calls `requestLANScan()`: it must not send anything.

- [x] **Step 8: Build and count the devices**

Run the `xcodebuild` line. Expected: `** BUILD SUCCEEDED **`; no warnings in `Symbiodock/System`, `AppDelegate` or `IslandMenu`.

The neighbour table is only given to an app started through LaunchServices, so run the hook through `open` and send its output to a file:

```bash
pkill -x Symbiodock; sleep 2
OUT=$(mktemp -d)/system-loop.txt
open --stdout "$OUT" --stderr "$OUT" --env SYMBIODOCK_PRINT_SYSTEM=loop build/Build/Products/Debug/Symbiodock.app
sleep 32; cat "$OUT"
```

Expected: the same six lines as before, now with device lists: 0 lists while the island is closed or on another tab; in "System tab shown, 7 s" one list (read on the first pass), a device count of at least 2 (the router and this Mac; on the owner's network 5 or 6) and `can scan true`. If `open` does not know `--stdout` (`open --help`), say so in the report and check the count through the log instead (`log show --last 2m --predicate 'subsystem == "com.yigtwxx.Symbiodock" && category == "system"'` shows nothing for a passive read, so then add a temporary `Self.log.notice("known: \(known.devices.count, privacy: .public)")`, read it, and remove it again).

If the count is 0 through `open` as well, stop and report: the table is not readable in this configuration and the plan needs a decision.

Do not press `Scan` and do not call `scan()` from anything: the owner does that.

- [x] **Step 9: Commit**

```bash
git add -A Symbiodock docs/superpowers/plans/2026-11-21-system-tab-b.md
git commit -m "feat(system): know the devices on the network, scan on request" -m "Showing the tab only reads the neighbours the Mac already has. The sweep and the name queries run when the state says Scan was pressed, and at no other time: on a network that is not the owner's, an automatic sweep would look like an attack."
git push origin main
```

---

### Task 4: The panel

**Files:**
- Modify: `Symbiodock/Island/System/SystemContent.swift` (`SystemContent`'s properties and body, and `DevicesPanel`), `Symbiodock/Island/ExpandedIsland.swift` (the `.system` case and `summary`), `Symbiodock/System/DemoSystem.swift` (`DemoSystem.apply`), `Symbiodock/App/DebugRender.swift`

**Interfaces:**
- Consumes: `LANDevice`, `LANScanState`, `LANLabels.count`, `IslandState.lanDevices`, `.canScanLAN`, `.lanScan`, `.requestLANScan()`, `.setLANDevices(_:canScan:)`, `.finishLANScan(blocked:)`; `SystemPalette.down`; `PanelCaption`, `systemPanel()` (private in `SystemContent.swift`).
- Produces: `SystemContent(snapshot:history:devices:scan:canScan:topInset:onScan:)`; `DemoSystem.apply` accepts `"1"`, `"hot"`, `"scanning"`, `"denied"`.

- [x] **Step 1: The page takes the devices**

In `Symbiodock/Island/System/SystemContent.swift`, `SystemContent`:

- After `let history: NetworkHistory`, add:

```swift
    var devices: [LANDevice] = []
    var scan: LANScanState = .idle
    var canScan = false
```

- After `let topInset: CGFloat`, add:

```swift
    /// `Scan` was pressed.
    var onScan: () -> Void = {}
```

- In `body`, replace `DevicesPanel()` with:

```swift
            DevicesPanel(devices: devices, scan: scan, canScan: canScan, onScan: onScan)
```

- [x] **Step 2: The panel**

Replace `DevicesPanel` (the whole private struct and its doc comment) with:

```swift
/// The devices on the network: those the Mac already knows, and after `Scan` everything that
/// answered. The list changes only when a new one arrives.
private struct DevicesPanel: View {
    let devices: [LANDevice]
    let scan: LANScanState
    let canScan: Bool
    let onScan: () -> Void

    private static let rowHeight: CGFloat = 20
    /// More rows than this are scrolled, and the list fades out at its lower edge.
    private static let visibleRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                PanelCaption("DEVICES")
                if !devices.isEmpty { count }
                Spacer(minLength: 0)
                if canScan { scanButton }
            }
            .frame(height: 16)
            if devices.isEmpty {
                Spacer(minLength: 0)
                Text(SystemLabels.missing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("No devices known")
                Spacer(minLength: 0)
            } else {
                list.padding(.top, 3)
            }
            if scan == .blocked {
                Text("Local Network access needed")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
        }
        .systemPanel()
    }

    private var count: some View {
        Text("\(devices.count)")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel(LANLabels.count(devices.count))
    }

    private var scanButton: some View {
        Button(action: onScan) {
            Text(scan == .scanning ? "Scanning…" : "Scan")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(scan == .scanning ? 0.4 : 0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(scan == .scanning)
        .accessibilityHint("Looks for every device on this network")
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(devices) { device in
                    row(device)
                }
            }
        }
        .mask {
            // Fading out at the lower edge says that the list goes on.
            if devices.count > Self.visibleRows {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .black.opacity(0.12), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            } else {
                Rectangle()
            }
        }
    }

    private func row(_ device: LANDevice) -> some View {
        HStack(spacing: 6) {
            dot(device.kind)
                .frame(width: 5, height: 5)
            Text(device.title)
                .font(.system(size: 11, weight: device.isNamed ? .medium : .regular).monospacedDigit())
                .foregroundStyle(.white.opacity(device.isNamed ? 1 : 0.55))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if device.isNamed {
                // The end of the address tells two devices of the same name apart.
                Text(device.address.suffix)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.title)
        .accessibilityValue(device.address.text)
    }

    @ViewBuilder
    private func dot(_ kind: LANDevice.Kind) -> some View {
        switch kind {
        case .router: Circle().strokeBorder(SystemPalette.down, lineWidth: 1.2)
        case .thisMac: Circle().fill(.white)
        case .other: Circle().fill(.white.opacity(0.35))
        }
    }
}
```

- [x] **Step 3: The island hands them over**

In `Symbiodock/Island/ExpandedIsland.swift`, replace the `.system` case:

```swift
                case .system:
                    SystemContent(
                        snapshot: state.system, history: state.networkHistory,
                        devices: state.lanDevices, scan: state.lanScan, canScan: state.canScanLAN,
                        topInset: metrics.height, onScan: { state.requestLANScan() })
```

In `summary`, add a branch after the Files one (before the Agents one):

```swift
        } else if state.selectedTab == .system, !state.lanDevices.isEmpty {
            Text(LANLabels.count(state.lanDevices.count))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
```

- [x] **Step 4: The demo and the renders**

In `Symbiodock/System/DemoSystem.swift`:

- Change the doc comment's list of values to: `1` a calm Mac, `hot` a busy and warm one, `scanning` a scan in flight, `denied` a scan macOS kept back.
- In `DemoSystem.apply`, `hot` stays `set == "hot"`. After the `state.setSystem(...)` call, add:

```swift
        func device(_ last: UInt8, _ name: String? = nil, _ kind: LANDevice.Kind = .other) -> LANDevice {
            LANDevice(address: LANAddress(192, 168, 1, last), name: name, kind: kind)
        }
        let everyone = [
            device(1, nil, .router), device(104, nil, .thisMac), device(101, "iPad"), device(100, "iPhone"),
            device(107, "Living Room TV"), device(110, "Printer"), device(102),
        ]
        // Without a scan the Mac knows only whom it has talked to.
        state.setLANDevices(set == "1" || set == "hot" ? everyone : Array(everyone.prefix(3)), canScan: true)
        if set == "scanning" || set == "denied" { state.requestLANScan() }
        if set == "denied" { state.finishLANScan(blocked: true) }
```

In `Symbiodock/App/DebugRender.swift`, the loop that writes `expanded-system` and `expanded-system-hot` gains the two new states:

```swift
        for (name, set) in [
            ("expanded-system", "1"), ("expanded-system-hot", "hot"),
            ("expanded-system-scanning", "scanning"), ("expanded-system-denied", "denied"),
        ] {
```

- [x] **Step 5: Build and look**

Run the `xcodebuild` line. Expected: `** BUILD SUCCEEDED **`.

Run `SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock`, then read the four `expanded-system*.png` renders with devices and `expanded-system-empty.png`. Check:

- `expanded-system.png`: caption `DEVICES`, a badge `7`, a `Scan` pill at the right of the same line; rows `Router .1` (teal ring), `This Mac .104` (white dot), `iPad .101`, `iPhone .100`, then the list fades out at its lower edge (`Living Room TV` partly visible); the header's right side says `7 devices`.
- `expanded-system-scanning.png`: three rows, the pill says `Scanning…` and is dimmer.
- `expanded-system-denied.png`: three rows, the pill says `Scan`, and under the list one line `Local Network access needed`.
- `expanded-system-empty.png`: the caption, a dash, no badge, no pill.
- Nothing is clipped at the panel's edge, the pill does not push the caption, long names end in an ellipsis before the address's end.
- The measures and the network panel look as before.

If the row text or the pill does not fit the 164-point panel (144 points inside), shorten the row before the panel: keep the widths from the Global Constraints of Part A.

- [x] **Step 6: Commit**

```bash
git add Symbiodock docs/superpowers/plans/2026-11-21-system-tab-b.md
git commit -m "feat(island): list the network's devices and offer a scan" -m "The panel shows whom the Mac already knows and counts them. Finding the rest takes a press on Scan: the owner asked that nothing be sent to a network by itself."
git push origin main
```

---

### Task 5: Record it

**Files:**
- Modify: `CLAUDE.md` (`Durum`, roadmap, "Doğrulanmamış varsayımlar"), the spec where the build differs from it, this plan (tick the boxes)

- [x] **Step 1: Run everything once more**

```bash
swift test --package-path Packages/SymbiodockCore 2>&1 | tail -3
xcodegen generate && xcodebuild -project Symbiodock.xcodeproj -scheme Symbiodock -configuration Debug -derivedDataPath build build 2>&1 | tail -3
SYMBIODOCK_RENDER_DIR=build/render build/Build/Products/Debug/Symbiodock.app/Contents/MacOS/Symbiodock
```

Expected: 829 tests pass, `** BUILD SUCCEEDED **`, the renders are written.

- [x] **Step 2: Write the status**

In `CLAUDE.md`: a `Durum` entry in Turkish with what this plan's steps showed (test count, renders, the passive device count through `open`, that no scan was run by anything but the owner); tick Faz 12 only if the owner has approved both parts, otherwise say that Part B's code is done and waits for the owner. In the spec: the three-minute rule is gone (the list is the table as it stands; the kernel ages its entries), the router's reverse DNS is not asked (it named nothing here and can block), the note reads `Local Network access needed`.

- [x] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers
git commit -m "docs: record part B of the System tab" -m "What was read without a scan, what the renders show and what is left for the owner to try."
git push origin main
```

Then stop and give the owner the list below.

## After the final review

The whole-change review found nothing critical: nothing is sent without a press, one press is one sweep, no name or address is logged or written. Its findings were fixed in `68744c9` and the commit after it; the code is the reference, not the listings above:

- Names are kept by address and hardware address (`LANIdentity`), not by address alone.
- A sweep counts as blocked when any device that had a hardware address before the sweep (this Mac and the router left out) was refused; the nine-in-ten rule only applies when there is no such device. The kernel itself refuses silent addresses on repeated scans.
- `Scan` is offered only where the router has a hardware address in the table (`LANDevices.canScan`), the sweep's socket is bound to the primary interface and the name queries go to it: nothing is swept into a tunnel.
- Names are asked in batches of 16; the router and this Mac are not asked.
- The menu item follows `state.lanScan`; the list's fade depends on the rows that fit (3 with the note), and the scrolled content has room below it.
- The hook prints the scan's state: `scan idle` on every line.

## Elle kontrol listesi

Çalıştır: `open build/Build/Products/Debug/Symbiodock.app`

1. `System` sekmesini aç: `Devices` panelinde `Scan`'e basmadan birkaç cihaz ve sayısı görünüyor (modem, bu Mac ve Mac'in konuştukları).
2. Başlığın sağında `N devices` yazıyor.
3. `Scan`'e bas: düğme `Scanning…` oluyor, 2-3 sn sonra liste büyüyor ya da aynı kalıyor, düğme `Scan`'e dönüyor.
4. İzin penceresi yeniden çıkıyor mu? (Çıkarsa `Allow`; çıkmaması beklenir.)
5. Adı olan cihazlar adıyla (iPhone, bu Mac `This Mac` olarak), diğerleri IP ile görünüyor.
6. Sıra: `Router`, `This Mac`, adı olanlar, sonra IP'ler.
7. Dörtten fazla cihaz varsa liste kaydırılıyor ve alt kenarı sönüyor; kaydırmak adayı sürüklemiyor.
8. `Scan`'e basmak adayı sürüklemiyor ya da kapatmıyor.
9. Sekmeyi kapatıp aç: cihaz adları duruyor (uygulama kapanana kadar).
10. System Settings → Privacy & Security → Local Network'te Symbiodock'u kapat, `Scan`'e bas: panelin altında ve sağ tık menüsünde `Local Network access needed` çıkıyor; menü maddesi ayarları açıyor. İzni geri aç, `Scan`'e bas: not gidiyor.
11. Wi-Fi'yi kapat: liste boşalıyor, `Scan` düğmesi yok.
12. `Scan`'e basmadıkça ağa bir şey gönderilmiyor (istersen `sudo tcpdump -i en0 'udp port 9 or udp port 5353'` ile bak: 9. port yalnızca basınca; 5353'te Symbiodock'tan gelen sorgular yalnızca basınca).
14. Bir-iki dakika içinde 6 kez `Scan`'e bas: `Local Network access needed` notu **çıkmamalı**.
15. Varsa bir VPN aç: `Scan` düğmesi kayboluyor; kapatınca birkaç saniyede geri geliyor.
13. Activity Monitor'de Symbiodock: sekme açıkken CPU yine %1 civarı ya da altı.
