import SwiftUI
import SymbiodockCore

struct IslandView: View {
    let state: IslandState
    let notch: CGRect
    let onCommand: (PlaybackCommand) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = IslandLayout.frame(
                phase: state.phase, notch: notch, screenSize: proxy.size, hasTrack: state.hasTrack)
            let radius: CGFloat = state.phase == .expanded ? 24 : 10

            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: 0,
                style: .continuous)
                .fill(.black)
                .overlay { content }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.phase)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.hasTrack)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .expanded:
            ExpandedContent(info: state.nowPlaying, topInset: notch.height, onCommand: onCommand)
                .transition(.opacity)
        case .collapsed:
            if let info = state.nowPlaying {
                CollapsedContent(info: info, notchWidth: notch.width)
                    .transition(.opacity)
            }
        }
    }
}
