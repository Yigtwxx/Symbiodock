import Darwin
import Foundation
import SymbiodockCore

/// The processor's and the memory's counters, from the kernel's host statistics. No
/// permission is needed.
enum HostSampler {
    /// Asked for once: every call of `mach_host_self` adds a reference to the port.
    private static let host = mach_host_self()

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let (user, system, idle, nice) = info.cpu_ticks
        let busy = UInt64(user) + UInt64(system) + UInt64(nice)
        return CPUTicks(busy: busy, total: busy + UInt64(idle))
    }

    static func memory() -> MemoryUse? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        let pages = MemoryPages(
            internalPages: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
            wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count))
        return MemoryUse(
            used: MemoryUsage.used(pages, pageSize: UInt64(pageSize)),
            total: ProcessInfo.processInfo.physicalMemory)
    }
}
