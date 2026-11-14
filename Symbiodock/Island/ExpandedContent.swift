import SwiftUI
import SymbiodockCore

/// Track details and playback controls, or an idle message.
struct ExpandedContent: View {
    let info: NowPlayingInfo?
    /// Height of the notch; nothing can be shown behind it.
    let topInset: CGFloat
    let onCommand: (PlaybackCommand) -> Void

    var body: some View {
        Group {
            if let info {
                track(info)
            } else {
                idle
            }
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idle: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Three rows that share whatever height the island has: at the notch that is little,
    /// floating at an edge it is more, and the rows spread out instead of leaving a gap.
    private func track(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkView(data: info.artworkData, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.artist.isEmpty ? info.sourceName : info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                LevelBars(isPlaying: info.isPlaying)
                    .opacity(info.isPlaying ? 1 : 0.4)
            }
            Spacer(minLength: 6)
            ProgressRow(info: info)
            Spacer(minLength: 4)
            HStack(spacing: 30) {
                control("backward.fill", size: 15, label: "Previous", command: .previous)
                control(
                    info.isPlaying ? "pause.fill" : "play.fill", size: 19,
                    label: info.isPlaying ? "Pause" : "Play",
                    command: .togglePlayPause)
                control("forward.fill", size: 15, label: "Next", command: .next)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func control(
        _ symbol: String, size: CGFloat, label: String, command: PlaybackCommand
    ) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 40, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(ControlButtonStyle())
        .accessibilityLabel(label)
    }
}

/// White glyph that dips and dims while pressed, so a click is felt even without hover.
private struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.95))
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Elapsed time, a display-only bar, and the track's length. Nothing when the source gives
/// no position (a live stream): the rows around it then move closer together.
private struct ProgressRow: View {
    let info: NowPlayingInfo

    var body: some View {
        if info.isPlaying {
            // Ticks once per second, and only while it is on screen and something plays.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                row(at: context.date)
            }
        } else {
            row(at: Date())
        }
    }

    @ViewBuilder
    private func row(at date: Date) -> some View {
        if let fraction = PlaybackProgress.fraction(for: info, at: date),
           let elapsed = PlaybackProgress.elapsed(for: info, at: date),
           let duration = info.duration {
            HStack(spacing: 8) {
                time(elapsed)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: max(proxy.size.width * fraction, 4))
                    }
                }
                .frame(height: 4)
                time(duration)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Self.clock(elapsed)) of \(Self.clock(duration))")
        }
    }

    private func time(_ seconds: TimeInterval) -> some View {
        Text(Self.clock(seconds))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
            .frame(minWidth: 28)
    }

    /// 97 → "1:37", 3725 → "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
