import Foundation

public enum TemperatureSensor: Equatable, Sendable {
    case cpu
    case gpu
}

/// Which keys of the System Management Controller are temperatures of the chip, and how
/// many readings become one number.
///
/// Measured on an M4 Pro (2026-11-21): about 100 keys begin with `Tp` or `Te` (performance
/// and efficiency cores) and 22 with `Tg` (graphics). Most do not read below 40 °C and a few
/// hold a peak, so the median is taken, not the mean. Reading one key takes about 170 µs,
/// so only a spread subset is read each time. Other chips name their keys differently.
public enum TemperatureKeys {
    /// Readings outside are sensors that are absent or asleep.
    public static let validRange: ClosedRange<Double> = 10...120
    /// At most this many keys are read each time.
    public static let cpuLimit = 24
    public static let gpuLimit = 8

    public static func sensor(forKey name: String) -> TemperatureSensor? {
        guard name.utf8.count == 4 else { return nil }
        if name.hasPrefix("Tp") || name.hasPrefix("Te") { return .cpu }
        if name.hasPrefix("Tg") { return .gpu }
        return nil
    }

    /// At most `limit` of the items, evenly spread and in their order.
    public static func spread<Item>(_ items: [Item], limit: Int) -> [Item] {
        guard limit > 0 else { return [] }
        guard items.count > limit else { return items }
        return (0..<limit).map { items[$0 * items.count / limit] }
    }

    /// The value many keys do not read below (measured on an M4 Pro). A key that reads exactly
    /// this says only "at most this".
    public static let floor = 40.0

    /// One number for the readings within the valid range; nil when there is none.
    ///
    /// Normally the median. While more than a quarter of the keys sit exactly on the floor the
    /// chip is cooler than the floor, and the median would stick at it: then the mean of the
    /// keys that do read below it is taken (they have no floor), or the floor itself when
    /// there is none.
    public static func typical(_ values: [Double]) -> Double? {
        let valid = values.filter { validRange.contains($0) }.sorted()
        guard !valid.isEmpty else { return nil }
        let onFloor = valid.filter { $0 == floor }.count
        if onFloor * 4 > valid.count {
            let below = valid.filter { $0 < floor }
            return below.isEmpty ? floor : below.reduce(0, +) / Double(below.count)
        }
        let middle = valid.count / 2
        return valid.count % 2 == 1 ? valid[middle] : (valid[middle - 1] + valid[middle]) / 2
    }
}
