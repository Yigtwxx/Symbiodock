import Foundation

/// When the next scan for agent sessions may start. A changed session file wakes the
/// scanner; a burst of changes must not turn into a burst of scans.
public enum ScanPacing {
    /// Two scans never start closer together than this.
    public static let minimumGap: TimeInterval = 0.25

    /// How long a scan asked for at `now` waits, the last one having started at `lastStart`.
    public static func delay(sinceLastStart lastStart: Date?, now: Date) -> TimeInterval {
        guard let lastStart else { return 0 }
        return min(max(minimumGap - now.timeIntervalSince(lastStart), 0), minimumGap)
    }
}
