import Foundation

/// The processor's tick counters since boot, summed over the cores.
public struct CPUTicks: Equatable, Sendable {
    /// Ticks spent working: user, system and nice.
    public var busy: UInt64
    /// All ticks, idle included.
    public var total: UInt64

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public enum CPUUsage {
    /// The share of the time between two readings the processor was busy, 0...1. Nil without
    /// two readings, and when the counters did not advance: the kernel's are 32-bit and wrap.
    public static func fraction(previous: CPUTicks?, current: CPUTicks?) -> Double? {
        guard let previous, let current, current.total > previous.total, current.busy >= previous.busy
        else { return nil }
        return min(1, Double(current.busy - previous.busy) / Double(current.total - previous.total))
    }
}

/// The page counts the kernel reports, as far as "memory used" needs them.
public struct MemoryPages: Equatable, Sendable {
    /// Anonymous memory: what apps allocated.
    public var internalPages: UInt64
    /// The part of it the system may take back at once.
    public var purgeable: UInt64
    public var wired: UInt64
    /// Pages the compressor itself occupies.
    public var compressed: UInt64

    public init(internalPages: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) {
        self.internalPages = internalPages
        self.purgeable = purgeable
        self.wired = wired
        self.compressed = compressed
    }
}

public struct MemoryUse: Equatable, Sendable {
    public var used: UInt64
    public var total: UInt64

    public init(used: UInt64, total: UInt64) {
        self.used = used
        self.total = total
    }

    /// 0...1; 0 while the total is unknown.
    public var fraction: Double {
        total > 0 ? min(1, Double(used) / Double(total)) : 0
    }
}

public enum MemoryUsage {
    /// Bytes in use as Activity Monitor counts them: app memory, wired and compressed.
    public static func used(_ pages: MemoryPages, pageSize: UInt64) -> UInt64 {
        let app = pages.internalPages > pages.purgeable ? pages.internalPages - pages.purgeable : 0
        return (app + pages.wired + pages.compressed) * pageSize
    }
}

/// The byte counters of one network interface since it came up.
public struct NetworkCounters: Equatable, Sendable {
    public var interface: String
    public var received: UInt64
    public var sent: UInt64

    public init(interface: String, received: UInt64, sent: UInt64) {
        self.interface = interface
        self.received = received
        self.sent = sent
    }
}

/// Bytes per second.
public struct NetworkSpeed: Equatable, Sendable {
    public var down: Double
    public var up: Double

    public init(down: Double, up: Double) {
        self.down = down
        self.up = up
    }
}

public enum NetworkRate {
    /// Two readings further apart than this are not compared: the Mac slept in between, and
    /// the average over the gap would say nothing about now.
    public static let maximumGap: TimeInterval = 10

    /// The speed between two readings of the same interface. Nil across a gap, when the
    /// counters went backwards (the interface came up again) or the interface changed.
    public static func speed(
        previous: NetworkCounters?, current: NetworkCounters?, elapsed: TimeInterval
    ) -> NetworkSpeed? {
        guard let previous, let current, previous.interface == current.interface,
              elapsed > 0, elapsed <= maximumGap,
              current.received >= previous.received, current.sent >= previous.sent
        else { return nil }
        return NetworkSpeed(
            down: Double(current.received - previous.received) / elapsed,
            up: Double(current.sent - previous.sent) / elapsed)
    }
}
