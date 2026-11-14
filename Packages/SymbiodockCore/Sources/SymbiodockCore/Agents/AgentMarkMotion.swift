import Foundation

/// How the "needs input" mark moves: its centre dot knocks twice, and each knock sends one
/// ring outward while it fades. Pure functions of time, so the views only play them.
public enum AgentMarkMotion {
    /// Seconds from the start of one pair of knocks to the start of the next.
    public static let knockPeriod: TimeInterval = 2.4
    /// Seconds one knock takes; the second knock follows the first directly.
    public static let knockLength: TimeInterval = 0.3
    /// Seconds a ring takes to reach twice the mark's size and fade away.
    public static let rippleLength: TimeInterval = 0.9
    /// How much larger the dot is at the height of a knock.
    public static let knockGrowth = 0.35

    /// The dot's scale `beat` seconds into a period: two knocks, then rest at 1.
    public static func dotScale(atBeat beat: TimeInterval) -> Double {
        guard beat >= 0, beat < 2 * knockLength else { return 1 }
        let local = beat.truncatingRemainder(dividingBy: knockLength) / knockLength
        return 1 + knockGrowth * sin(.pi * local)
    }

    /// 0...1 through a ring that was sent `start` seconds into the period; nil before and
    /// after it. The first ring leaves at 0, the second with the second knock.
    public static func ripple(atBeat beat: TimeInterval, from start: TimeInterval) -> Double? {
        let value = (beat - start) / rippleLength
        return value >= 0 && value < 1 ? value : nil
    }
}
