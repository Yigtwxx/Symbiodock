import Foundation

/// How the media level bars move. Decorative: they do not follow the audio. Every bar's
/// height is `0.35 + 0.65 * |sin(time * speed + phase)|` of the full height, which repeats
/// every `period(ofBar:)` seconds, so a repeating animation sampled over one period
/// reproduces it exactly.
public enum LevelBarsMotion {
    public static let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]
    public static let phases: [Double] = [0, 1.7, 0.6, 2.9]
    public static var barCount: Int { speeds.count }
    /// The height of a bar while nothing plays, as a share of the full height.
    public static let restLevel = 0.25

    /// Seconds after which bar `index` is where it was: |sin| repeats every half turn.
    public static func period(ofBar index: Int) -> TimeInterval {
        .pi / speeds[index]
    }

    /// Bar `index`'s height at `time` seconds, 0.35...1 of the full height.
    public static func level(ofBar index: Int, at time: TimeInterval) -> Double {
        0.35 + 0.65 * abs(sin(time * speeds[index] + phases[index]))
    }
}
