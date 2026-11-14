import SwiftUI
import SymbiodockCore

/// What the island shows collapsed when it is docked at an edge or corner: there is no
/// notch to leave room for, so the title fits between the artwork and the level bars.
/// With nothing playing it still says what it is, because a docked island never hides.
struct FloatingCollapsedContent: View {
    let info: NowPlayingInfo?
    var attention: AgentRowState?

    var body: some View {
        HStack(spacing: 8) {
            if let info {
                ArtworkView(data: info.artworkData, size: 22)
                Text(info.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
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
                Text("Nothing playing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, info == nil ? 14 : 8)
    }
}
