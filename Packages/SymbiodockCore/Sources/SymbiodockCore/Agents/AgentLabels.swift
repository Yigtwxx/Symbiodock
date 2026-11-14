import Foundation

/// The words the Agents tab uses.
public enum AgentLabels {
    /// 30 → "<1m", 125 → "2m", 3840 → "1h 4m".
    public static func duration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 60 else { return "<1m" }
        // Clamp first: Int(_:) traps for a huge finite value (ten years of minutes is plenty).
        let minutes = Int(min(interval / 60, 5_256_000))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    public static func status(_ state: AgentRowState, since: Date, now: Date) -> String {
        let elapsed = duration(now.timeIntervalSince(since))
        switch state {
        case .needsInput: return "Needs input"
        case .working: return "Working \(elapsed)"
        case .finished: return "Done \(elapsed)"
        case .running: return "Running"
        case .idle: return "Idle \(elapsed)"
        }
    }

    /// "1 needs input · 2 working"; nil when both counts are zero.
    public static func summary(needsInput: Int, working: Int) -> String? {
        var parts: [String] = []
        if needsInput > 0 { parts.append("\(needsInput) needs input") }
        if working > 0 { parts.append("\(working) working") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
