import SwiftUI
import SymbiodockCore

/// Track details and playback controls, or an idle message. Two sources that play at the
/// same time get a row each, with their own controls.
struct ExpandedContent: View {
    let slots: [NowPlayingSlot]
    /// Height of the notch; nothing can be shown behind it.
    let topInset: CGFloat
    let onCommand: (PlaybackCommand, NowPlayingOrigin) -> Void
    /// How loud the players are that have a volume of their own.
    var volumes: [VolumeTarget: Double] = [:]
    var onVolume: (VolumeRequest) -> Void = { _ in }

    /// The players shown that have a volume of their own.
    private var targets: [VolumeTarget] {
        slots.compactMap { VolumeTarget.target(for: $0.info) }
    }

    /// Room under the last row. The island's bottom corners are round, so what sits right
    /// above the edge needs about as much air as the sides give it.
    private static let bottomMargin: CGFloat = 16

    private var showsAnyVolume: Bool {
        targets.contains { volumes[$0] != nil }
    }

    var body: some View {
        Group {
            if slots.count > 1 {
                VStack(spacing: 0) {
                    ForEach(slots) { slot in
                        row(slot).frame(maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, Self.bottomMargin)
            } else if let slot = slots.first {
                track(slot)
            } else {
                idle
            }
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Asked whenever the tab comes up: the volume may have changed in the player.
        .task(id: targets) {
            for target in targets { onVolume(.read(target)) }
        }
    }

    /// The player's volume at the far right; nothing for a source without one of its own.
    @ViewBuilder
    private func volume(_ slot: NowPlayingSlot) -> some View {
        if let target = VolumeTarget.target(for: slot.info), let value = volumes[target] {
            VolumeSlider(
                target: target, value: value, tint: ArtworkCache.tint(for: slot.info.artworkData)
            ) { onVolume(.set(target, $0)) }
        }
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
    private func track(_ slot: NowPlayingSlot) -> some View {
        let info = slot.info
        return HStack(spacing: 16) {
            trackRows(slot)
            volume(slot)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, Self.bottomMargin)
    }

    private func trackRows(_ slot: NowPlayingSlot) -> some View {
        let info = slot.info
        return VStack(spacing: 0) {
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
                LevelBars(isPlaying: info.isPlaying, artwork: info.artworkData)
                    .opacity(info.isPlaying ? 1 : 0.4)
            }
            Spacer(minLength: 6)
            ProgressRow(info: info)
            Spacer(minLength: 4)
            HStack(spacing: 30) {
                controls(slot, glyph: 15, width: 40)
            }
        }
    }

    /// One of two sources: everything of `track` on a single line, the position as a thin
    /// bar under the names.
    private func row(_ slot: NowPlayingSlot) -> some View {
        let info = slot.info
        return HStack(spacing: 10) {
            ArtworkView(data: info.artworkData, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(info.artist.isEmpty ? info.sourceName : info.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                ProgressRow(info: info, isCompact: true)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                controls(slot, glyph: 12, width: 30)
            }
            LevelBars(isPlaying: info.isPlaying, artwork: info.artworkData)
                .opacity(info.isPlaying ? 1 : 0.4)
            if VolumeTarget.target(for: info).flatMap({ volumes[$0] }) != nil {
                volume(slot)
                    .padding(.vertical, 4)
            } else if showsAnyVolume {
                // The other row has a slider: keep the two rows' buttons in line.
                Color.clear.frame(width: VolumeSlider.width)
            }
        }
        .opacity(info.isPlaying ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(info.sourceName)
    }

    @ViewBuilder
    private func controls(_ slot: NowPlayingSlot, glyph: CGFloat, width: CGFloat) -> some View {
        let isPlaying = slot.info.isPlaying
        control("backward.fill", size: glyph, width: width, label: "Previous", slot, .previous)
        control(
            isPlaying ? "pause.fill" : "play.fill", size: glyph + 4, width: width,
            label: isPlaying ? "Pause" : "Play", slot, .togglePlayPause)
        control("forward.fill", size: glyph, width: width, label: "Next", slot, .next)
    }

    private func control(
        _ symbol: String, size: CGFloat, width: CGFloat, label: String,
        _ slot: NowPlayingSlot, _ command: PlaybackCommand
    ) -> some View {
        Button {
            onCommand(command, slot.origin)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: width, height: 24)
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
    /// The bar alone, thinner and without the times.
    var isCompact = false

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
                if !isCompact { time(elapsed) }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        BarFill(tint: ArtworkCache.tint(for: info.artworkData))
                            .clipShape(Capsule())
                            .frame(width: max(proxy.size.width * fraction, 4))
                    }
                }
                .frame(height: isCompact ? 2.5 : 4)
                if !isCompact { time(duration) }
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
