import SwiftUI
import SymbiodockCore

/// What the island shows collapsed against the left or right edge, where it is a strip
/// along the edge: the platform on top, the title running down the middle, the level bars
/// at the bottom. With nothing playing it still says what it is.
struct SideCollapsedContent: View {
    let info: NowPlayingInfo?
    var attention: AgentRowState?

    private static let iconSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 8) {
            if let info {
                PlatformIcon(info: info, size: Self.iconSize)
                RotatedLine(text: info.title)
                    .foregroundStyle(.white)
                if let attention {
                    AgentStatusMark(state: attention)
                } else {
                    LevelBars(isPlaying: info.isPlaying)
                        .opacity(info.isPlaying ? 1 : 0.4)
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(height: Self.iconSize)
                RotatedLine(text: "Nothing playing")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One line of text turned a quarter turn clockwise, so it reads from the top down and is
/// cut off at the bottom when it does not fit.
struct RotatedLine: View {
    let text: String

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                // Laid out along the strip's free height, then turned into place.
                .frame(width: proxy.size.height, height: proxy.size.width, alignment: .leading)
                .rotationEffect(.degrees(90))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
