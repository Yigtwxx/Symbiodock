import SwiftUI
import SymbiodockCore

/// What the island shows collapsed when it floats at an edge or corner: there is no
/// notch to leave room for, so the title fits between the artwork and the level bars.
struct FloatingCollapsedContent: View {
    let info: NowPlayingInfo

    var body: some View {
        HStack(spacing: 8) {
            ArtworkView(data: info.artworkData, size: 22)
            Text(info.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            LevelBars(isPlaying: info.isPlaying)
        }
        .padding(.horizontal, 10)
    }
}
