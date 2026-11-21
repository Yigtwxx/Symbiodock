#if DEBUG
import Darwin
import Foundation
import SystemConfiguration
import dnssd

/// A one-off experiment for the devices panel, not part of the app's behaviour:
/// `open --env SYMBIODOCK_PROBE_LAN=/path/to/report.txt build/Build/Products/Debug/Symbiodock.app`.
/// It must be started through `open`, so that macOS attributes the Local Network permission
/// to Symbiodock and not to the terminal. It reads the neighbour table, sends one empty UDP
/// datagram to every address of the subnet (which makes macOS ask for the permission), reads
/// the table again for a minute, looks the found addresses' names up, writes what it saw to
/// the report file and quits. The report holds addresses and names of this network: it stays
/// on this Mac and is never logged.
@MainActor
enum LANProbe {
    /// True when the probe took over: the caller must not build the island.
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SYMBIODOCK_PROBE_LAN"] else { return false }
        Task.detached {
            LANProbeRun(reportPath: path).run()
            exit(0)
        }
        return true
    }
}

private struct Neighbour {
    var address: [UInt8]
    var hardware: [UInt8]?
    var text: String { address.map(String.init).joined(separator: ".") }
}

private final class LANProbeRun: @unchecked Sendable {
    private let reportPath: String
    private var lines: [String] = []
    private let started = Date()

    init(reportPath: String) {
        self.reportPath = reportPath
    }

    private func note(_ line: String) {
        lines.append(String(format: "%5.1f s  ", Date().timeIntervalSince(started)) + line)
        try? lines.joined(separator: "\n").appending("\n").write(toFile: reportPath, atomically: true, encoding: .utf8)
    }

    func run() {
        guard let store = SCDynamicStoreCreate(nil, "SymbiodockProbe" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let interface = global["PrimaryInterface"] as? String,
              let own = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(interface)/IPv4" as CFString)
                as? [String: Any],
              let address = (own["Addresses"] as? [String])?.first.flatMap(Self.bytes),
              let mask = (own["SubnetMasks"] as? [String])?.first.flatMap(Self.bytes)
        else {
            note("no primary IPv4 interface")
            return
        }
        let router = (global["Router"] as? String) ?? "-"
        let hosts = Self.hosts(address: address, mask: mask)
        note("interface \(interface) router \(router) mask \(mask.map(String.init).joined(separator: ".")) hosts \(hosts.count)")

        let (before, beforeBytes) = neighbours()
        note("before any packet: table \(beforeBytes) bytes, \(before.count) entries, arp tool \(arpToolCount()) lines")

        var seen: [Neighbour] = []
        var stable = 0
        for round in 1...20 {
            let outcome = sweep(hosts)
            Thread.sleep(forTimeInterval: 1.5)
            let (found, bytes) = neighbours()
            let complete = found.filter { $0.hardware != nil }
            note("round \(round): sent \(outcome.sent), errors \(outcome.errors), table \(bytes) bytes, "
                + "\(found.count) entries (\(complete.count) with hardware address), arp tool \(arpToolCount()) lines")
            if complete.count > 0, complete.count == seen.count { stable += 1 } else { stable = 0 }
            seen = complete
            if stable >= 2 { break }
            Thread.sleep(forTimeInterval: 1.5)
        }

        if let (dump, _) = Optional(rawTable()), dump.count >= 2 {
            let length = Int(dump[0]) | Int(dump[1]) << 8
            note("first table message, \(length) bytes: " + dump.prefix(min(length, dump.count)).map { String(format: "%02x", $0) }.joined())
        }
        for neighbour in seen {
            let hardware = neighbour.hardware.map { bytes in
                let local = bytes[0] & 0x02 != 0 ? "random" : "vendor"
                return String(format: "%02x:%02x:%02x:xx:xx:xx (%@)", bytes[0], bytes[1], bytes[2], local)
            } ?? "-"
            let dnsStart = Date()
            let dns = reverseDNS(neighbour.address) ?? "-"
            let dnsTime = Date().timeIntervalSince(dnsStart)
            let mdnsStart = Date()
            let mdns = multicastName(neighbour.address) ?? "-"
            let mdnsTime = Date().timeIntervalSince(mdnsStart)
            note(String(
                format: "%@  %@  dns %@ (%.2f s)  mdns %@ (%.2f s)", neighbour.text, hardware, dns, dnsTime,
                mdns, mdnsTime))
        }
        note("done: \(seen.count) devices")
    }

    // MARK: Addresses

    private static func bytes(_ dotted: String) -> [UInt8]? {
        let parts = dotted.split(separator: ".").compactMap { UInt8($0) }
        return parts.count == 4 ? parts : nil
    }

    /// Every host address of the subnet, the network and broadcast addresses left out; none
    /// when the subnet is wider than /22.
    private static func hosts(address: [UInt8], mask: [UInt8]) -> [[UInt8]] {
        func word(_ bytes: [UInt8]) -> UInt32 { bytes.reduce(0) { $0 << 8 | UInt32($1) } }
        let maskWord = word(mask)
        let network = word(address) & maskWord
        let size = ~maskWord
        guard size >= 3, size <= 1023 else { return [] }
        return (1..<size).map { offset in
            let host = network | offset
            return [UInt8(host >> 24), UInt8(host >> 16 & 0xFF), UInt8(host >> 8 & 0xFF), UInt8(host & 0xFF)]
        }
    }

    // MARK: Sweep

    private func sweep(_ hosts: [[UInt8]]) -> (sent: Int, errors: [Int32: Int]) {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return (0, [errno: 1]) }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        var sent = 0
        var errors: [Int32: Int] = [:]
        for host in hosts {
            var target = sockaddr_in()
            target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            target.sin_family = sa_family_t(AF_INET)
            // The discard port: nothing answers, the kernel only has to find the neighbour.
            target.sin_port = UInt16(9).bigEndian
            target.sin_addr.s_addr = host.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            let result = withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, nil, 0, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result >= 0 { sent += 1 } else { errors[errno, default: 0] += 1 }
        }
        return (sent, errors)
    }

    // MARK: Neighbour table

    private func rawTable() -> ([UInt8], Int32) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0 else { return ([], errno) }
        guard length > 0 else { return ([], 0) }
        length += 1024
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return ([], errno) }
        return (Array(buffer.prefix(length)), 0)
    }

    private func neighbours() -> ([Neighbour], Int) {
        let (dump, _) = rawTable()
        let headerSize = MemoryLayout<rt_msghdr>.size
        var entries: [Neighbour] = []
        var offset = 0
        while offset + headerSize <= dump.count {
            let length = Int(dump[offset]) | Int(dump[offset + 1]) << 8
            guard length >= headerSize, offset + length <= dump.count else { break }
            defer { offset += length }
            let inet = offset + headerSize
            guard inet + 8 <= offset + length, dump[inet + 1] == UInt8(AF_INET) else { continue }
            let address = Array(dump[(inet + 4)..<(inet + 8)])
            let link = inet + max(4, (Int(dump[inet]) + 3) & ~3)
            guard link + 8 <= offset + length, dump[link + 1] == UInt8(AF_LINK) else { continue }
            let nameLength = Int(dump[link + 5]), hardwareLength = Int(dump[link + 6])
            let start = link + 8 + nameLength
            var hardware: [UInt8]?
            if hardwareLength == 6, start + 6 <= offset + length { hardware = Array(dump[start..<(start + 6)]) }
            // Multicast and broadcast entries are not devices.
            if address[0] >= 224 || address == [255, 255, 255, 255] { continue }
            if let hardware, hardware == [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] { continue }
            entries.append(Neighbour(address: address, hardware: hardware))
        }
        return (entries, dump.count)
    }

    /// What Apple's own tool sees, for comparison: the lines that name a hardware address.
    private func arpToolCount() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-an"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .filter { $0.contains(" at ") && !$0.contains("incomplete") && !$0.contains("ff:ff:ff:ff:ff:ff") && !$0.contains("(224.") }
            .count
    }

    // MARK: Names

    /// The name the configured DNS server (usually the router) has for the address.
    private func reverseDNS(_ address: [UInt8]) -> String? {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_addr.s_addr = address.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
            }
        }
        return result == 0 ? String(cString: host) : nil
    }

    private final class Answer {
        var name: String?
    }

    /// The name the device itself gives over multicast DNS, waited for up to two seconds.
    private func multicastName(_ address: [UInt8]) -> String? {
        let question = address.reversed().map(String.init).joined(separator: ".") + ".in-addr.arpa"
        let answer = Answer()
        var reference: DNSServiceRef?
        let callback: DNSServiceQueryRecordReply = { _, _, _, error, _, _, _, length, data, _, context in
            guard error == kDNSServiceErr_NoError, let data, let context, length > 0 else { return }
            let bytes = UnsafeRawBufferPointer(start: data, count: Int(length))
            // A domain name: length-prefixed labels up to a zero.
            var labels: [String] = []
            var index = 0
            while index < bytes.count, bytes[index] != 0 {
                let count = Int(bytes[index])
                guard count < 64, index + 1 + count <= bytes.count else { break }
                labels.append(String(decoding: bytes[(index + 1)..<(index + 1 + count)], as: UTF8.self))
                index += 1 + count
            }
            Unmanaged<Answer>.fromOpaque(context).takeUnretainedValue().name = labels.joined(separator: ".")
        }
        let status = DNSServiceQueryRecord(
            &reference, kDNSServiceFlagsForceMulticast, 0, question, UInt16(kDNSServiceType_PTR),
            UInt16(kDNSServiceClass_IN), callback, Unmanaged.passUnretained(answer).toOpaque())
        guard status == kDNSServiceErr_NoError, let reference else { return nil }
        defer { DNSServiceRefDeallocate(reference) }
        let descriptor = DNSServiceRefSockFD(reference)
        let deadline = Date().addingTimeInterval(2)
        while answer.name == nil, Date() < deadline {
            var readable = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let waited = poll(&readable, 1, 200)
            if waited > 0, DNSServiceProcessResult(reference) != kDNSServiceErr_NoError { break }
        }
        return answer.name
    }
}
#endif
