/// Decides whether and when to start a crashed helper again.
public struct RestartPolicy: Sendable {
    private let maxRestarts: Int
    private let stableRunTime: Duration
    private var restarts = 0

    public init(maxRestarts: Int = 3, stableRunTime: Duration = .seconds(60)) {
        self.maxRestarts = maxRestarts
        self.stableRunTime = stableRunTime
    }

    /// Call when a run of the helper has ended. Returns how long to wait before the next
    /// run, or nil when it should not be restarted any more.
    public mutating func delayAfterRun(lasting runTime: Duration) -> Duration? {
        // A helper that ran for a while was working; start counting again.
        if runTime > stableRunTime { restarts = 0 }
        guard restarts < maxRestarts else { return nil }
        restarts += 1
        return .seconds(1 << (restarts - 1))  // 1 s, 2 s, 4 s
    }
}
