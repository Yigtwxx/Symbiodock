import Foundation

/// How warm a temperature reads: the colour of its number.
public enum TemperatureTier: Equatable, Sendable {
    case normal
    case warm
    case hot
}

/// The words and numbers of the System tab.
public enum SystemLabels {
    /// Shown for a value that could not be read.
    public static let missing = "—"

    private static let gigabyte = 1_073_741_824.0

    /// 0.314 → "31%".
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return missing }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// 44.6 → "45°".
    public static func degrees(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite else { return missing }
        return "\(Int(celsius.rounded()))°"
    }

    /// Warm from 80 °C, hot from 95 °C, by the number that is shown.
    public static func tier(_ celsius: Double?) -> TemperatureTier {
        guard let celsius, celsius.isFinite else { return .normal }
        let shown = celsius.rounded()
        return shown >= 95 ? .hot : shown >= 80 ? .warm : .normal
    }

    /// Bytes per second in decimal units: "156 KB/s", "1.7 MB/s", "1.3 GB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        if value >= 999_950_000 { return String(format: "%.1f GB/s", value / 1_000_000_000) }
        if value >= 999_500 { return String(format: "%.1f MB/s", value / 1_000_000) }
        return "\(Int((value / 1_000).rounded())) KB/s"
    }

    /// Memory in binary gigabytes with one decimal, as Activity Monitor shows it: "18.5".
    public static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / gigabyte)
    }

    /// The installed memory: "48".
    public static func wholeGigabytes(_ bytes: UInt64) -> String {
        "\(Int((Double(bytes) / gigabyte).rounded()))"
    }
}
