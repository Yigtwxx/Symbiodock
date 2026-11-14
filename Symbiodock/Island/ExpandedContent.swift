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
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.top, topInset)
    }

    private func track(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ArtworkView(data: info.artworkData, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(info.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ProgressBar(info: info)
            HStack(spacing: 28) {
                control("backward.fill", label: "Previous", command: .previous)
                control(
                    info.isPlaying ? "pause.fill" : "play.fill",
                    label: info.isPlaying ? "Pause" : "Play",
                    command: .togglePlayPause)
                control("forward.fill", label: "Next", command: .next)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func control(_ symbol: String, label: String, command: PlaybackCommand) -> some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Display-only progress. Ticks once per second, and only while it is on screen.
private struct ProgressBar: View {
    let info: NowPlayingInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = PlaybackProgress.fraction(for: info, at: context.date) ?? 0
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }
}
