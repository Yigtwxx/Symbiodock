import Foundation

/// Where playback is at a given instant, derived from the last reported position.
public enum PlaybackProgress {
    public static func elapsed(for info: NowPlayingInfo, at now: Date) -> TimeInterval? {
        guard var elapsed = info.elapsed else { return nil }
        if info.isPlaying, let measuredAt = info.elapsedAt {
            elapsed += now.timeIntervalSince(measuredAt)
        }
        elapsed = max(elapsed, 0)
        if let duration = info.duration {
            elapsed = min(elapsed, duration)
        }
        return elapsed
    }

    /// 0...1, or nil when the position or the duration is unknown.
    public static func fraction(for info: NowPlayingInfo, at now: Date) -> Double? {
        guard let duration = info.duration, duration > 0,
              let elapsed = elapsed(for: info, at: now)
        else { return nil }
        return elapsed / duration
    }
}
