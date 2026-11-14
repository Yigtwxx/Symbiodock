import SwiftUI

/// Four bars that move while something is playing. Decorative: they do not follow the audio.
struct LevelBars: View {
    let isPlaying: Bool

    private static let speeds: [Double] = [5.1, 6.7, 4.3, 7.9]
    private static let phases: [Double] = [0, 1.7, 0.6, 2.9]
    private static let height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2.5, height: Self.height * level(index, at: time))
                }
            }
            .frame(height: Self.height)
        }
        .accessibilityHidden(true)
    }

    private func level(_ index: Int, at time: TimeInterval) -> CGFloat {
        guard isPlaying else { return 0.25 }
        return 0.35 + 0.65 * abs(sin(time * Self.speeds[index] + Self.phases[index]))
    }
}
