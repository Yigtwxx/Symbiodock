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

    /// Blocks for at most `timeout`, asking on the interface of `interfaceIndex` only. The
    /// host name as the device gave it, such as "Living-Room-TV.local"; nil when it did not
    /// answer.
    static func name(of address: LANAddress, interfaceIndex: UInt32, timeout: TimeInterval) -> String? {
        let answer = Answer()
        var reference: DNSServiceRef?
        let callback: DNSServiceQueryRecordReply = { _, flags, _, error, _, _, _, length, data, _, context in
            // A removal ("this record is gone") is not an answer.
            guard flags & kDNSServiceFlagsAdd != 0, error == kDNSServiceErr_NoError, let data, let context, length > 0 else { return }
            let bytes = Array(UnsafeRawBufferPointer(start: data, count: Int(length)))
            Unmanaged<Answer>.fromOpaque(context).takeUnretainedValue().host = LANNames.host(fromWire: bytes)
        }
        let status = DNSServiceQueryRecord(
            &reference, kDNSServiceFlagsForceMulticast, interfaceIndex, LANNames.reverseQuestion(for: address),
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
