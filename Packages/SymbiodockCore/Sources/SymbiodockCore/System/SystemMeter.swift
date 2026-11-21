import Foundation

/// The chip's temperatures in °C; nil where none could be read.
public struct Temperatures: Equatable, Sendable {
    public var cpu: Double?
    public var gpu: Double?

    public init(cpu: Double? = nil, gpu: Double? = nil) {
        self.cpu = cpu
        self.gpu = gpu
    }
}

/// What one look at the system gave: counters and momentary values, nothing derived yet.
public struct SystemReading: Equatable, Sendable {
    public var date: Date
    public var cpu: CPUTicks?
    public var memory: MemoryUse?
    /// 0...1.
    public var gpu: Double?
    /// Nil when the temperatures were not read this time; they are read less often.
    public var temperatures: Temperatures?
    /// The primary interface's counters; nil while there is no network.
    public var counters: NetworkCounters?

    public init(
        date: Date, cpu: CPUTicks?, memory: MemoryUse?, gpu: Double?, temperatures: Temperatures?,
        counters: NetworkCounters?
    ) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.temperatures = temperatures
        self.counters = counters
    }
}

/// What the System tab shows. A nil value could not be read and is drawn as a dash.
public struct SystemSnapshot: Equatable, Sendable {
    /// 0...1.
    public var cpu: Double?
    public var gpu: Double?
    public var memory: MemoryUse?
    public var temperatures: Temperatures
    /// Nil while offline, and for the one sample after the interface changed.
    public var network: NetworkSpeed?
    public var isOnline: Bool

    public init(
        cpu: Double?, gpu: Double?, memory: MemoryUse?, temperatures: Temperatures,
        network: NetworkSpeed?, isOnline: Bool
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.temperatures = temperatures
        self.network = network
        self.isOnline = isOnline
    }
}

/// The network speeds of the last minute, oldest first, for the graph.
public struct NetworkHistory: Equatable, Sendable {
    /// One sample every two seconds: a minute.
    public static let capacity = 30
    /// The graph's full height is never less than this, in bytes per second, so that the
    /// idle chatter of a quiet network stays near the floor.
    public static let minimumScale = 100_000.0

    public private(set) var samples: [NetworkSpeed] = []

    public init() {}

    public mutating func append(_ speed: NetworkSpeed) {
        samples.append(speed)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// The speed at the graph's full height: the fastest sample of either direction.
    public var scale: Double {
        samples.reduce(Self.minimumScale) { max($0, $1.down, $1.up) }
    }

    /// 0...1 per sample, on the shared scale.
    public var downFractions: [Double] {
        let scale = scale
        return samples.map { $0.down / scale }
    }

    public var upFractions: [Double] {
        let scale = scale
        return samples.map { $0.up / scale }
    }
}

/// Turns readings into what is shown. Use and speed come from two readings, so the first
/// one, and the first after a gap, only primes the meter.
public struct SystemMeter: Sendable {
    private var last: SystemReading?
    private var temperatures = Temperatures()
    public private(set) var history = NetworkHistory()

    public init() {}

    /// Nil when this reading could only prime the meter.
    public mutating func take(_ reading: SystemReading) -> SystemSnapshot? {
        let earlier = last
        last = reading
        if let read = reading.temperatures { temperatures = read }
        guard let earlier else { return nil }
        let elapsed = reading.date.timeIntervalSince(earlier.date)
        guard elapsed > 0, elapsed <= NetworkRate.maximumGap else {
            // The tab was hidden or the Mac slept: what the graph held is not the last minute.
            history.reset()
            return nil
        }
        let speed = NetworkRate.speed(previous: earlier.counters, current: reading.counters, elapsed: elapsed)
        if let speed {
            history.append(speed)
        } else if reading.counters == nil {
            history.reset()
        }
        return SystemSnapshot(
            cpu: CPUUsage.fraction(previous: earlier.cpu, current: reading.cpu), gpu: reading.gpu,
            memory: reading.memory, temperatures: temperatures, network: speed,
            isOnline: reading.counters != nil)
    }
}
