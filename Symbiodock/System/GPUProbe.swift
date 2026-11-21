import Foundation
import IOKit

/// How busy the graphics processor is, from the statistics its driver publishes in the
/// I/O registry (what Activity Monitor's GPU history shows). No permission is needed.
enum GPUProbe {
    /// 0...1; the busiest, where there is more than one. Nil when no driver reports it.
    static func utilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let property = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
            guard let statistics = property as? [String: Any],
                  let percent = statistics["Device Utilization %"] as? NSNumber
            else { continue }
            busiest = max(busiest ?? 0, min(1, max(0, percent.doubleValue / 100)))
        }
        return busiest
    }
}
