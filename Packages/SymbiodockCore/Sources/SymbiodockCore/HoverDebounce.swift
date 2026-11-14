/// Turns raw "pointer is inside / outside" samples into delayed hover changes.
public struct HoverDebounce<Instant: InstantProtocol> where Instant.Duration == Duration {
    /// The debounced value; starts false.
    public private(set) var isHovering = false
    private var pending: (value: Bool, deadline: Instant)?

    /// Creates a debounce that is not hovering and has nothing pending.
    public init() {}

    /// Feed a sample. Returns the instant at which `fire(now:)` should be called, or nil
    /// if nothing is pending (the sample matches the current value, or cancels a pending change).
    public mutating func pointer(inside: Bool, now: Instant) -> Instant? {
        guard inside != isHovering else {
            pending = nil
            return nil
        }
        if let pending, pending.value == inside { return pending.deadline }
        let delay = inside ? HoverTiming.enterDelay : HoverTiming.exitDelay
        let deadline = now.advanced(by: delay)
        pending = (inside, deadline)
        return deadline
    }

    /// Applies the pending change if its deadline has passed. Returns the new value when it changed.
    public mutating func fire(now: Instant) -> Bool? {
        guard let pending, pending.deadline <= now else { return nil }
        self.pending = nil
        isHovering = pending.value
        return pending.value
    }

    /// Drops any pending change and sets the value (used when the panel is rebuilt).
    public mutating func reset(to hovering: Bool) {
        pending = nil
        isHovering = hovering
    }
}
