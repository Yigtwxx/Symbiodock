import SwiftUI
import SymbiodockCore

/// Artwork in the left wing, level bars in the right wing, nothing over the notch itself.
/// While an agent wants attention, its status mark takes the place of the level bars.
struct CollapsedContent: View {
    let info: NowPlayingInfo
    /// A second source that plays at the same time.
    var behind: NowPlayingInfo?
    let notchWidth: CGFloat
    var attention: AgentRowState?

    var body: some View {
        HStack(spacing: 0) {
            ArtworkStack(front: info.artworkData, behind: behind, size: 20)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: notchWidth)
            Group {
                if let attention {
                    AgentStatusMark(state: attention)
                } else {
                    LevelBars(isPlaying: info.isPlaying)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
