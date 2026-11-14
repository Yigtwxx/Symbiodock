import SwiftUI
import SymbiodockCore

/// Artwork in the left wing, level bars in the right wing, nothing over the notch itself.
struct CollapsedContent: View {
    let info: NowPlayingInfo
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(data: info.artworkData, size: 20)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: notchWidth)
            LevelBars(isPlaying: info.isPlaying)
                .frame(maxWidth: .infinity)
        }
    }
}
