import SwiftUI
import SymbiodockCore

struct IslandView: View {
    let state: IslandState
    let geometry: IslandGeometry
    let session: DragSession
    let onCommand: (PlaybackCommand) -> Void

    private static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    var body: some View {
        GeometryReader { _ in
            switch state.phase {
            case .collapsed, .expanded:
                resting
            case .stretching, .detached, .settling:
                // Body, root and goo all move per frame; the session draws them together.
                DragLayer(session: session)
            }
        }
        .ignoresSafeArea()
    }

    private var resting: some View {
        let atNotch = state.anchor == .notch
        let frame = IslandLayout.frame(
            anchor: state.anchor, phase: state.phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            hasTrack: state.showsWings)
        // At the notch the island hangs from the display edge; anywhere else it is a capsule.
        let bottom: CGFloat = state.phase == .expanded ? 24 : (atNotch ? 10 : frame.height / 2)
        let top: CGFloat = atNotch ? 0 : bottom
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)

        return shape
            .fill(.black)
            .overlay { content(atNotch: atNotch) }
            .frame(width: frame.width, height: frame.height)
            // Content must not draw outside the shape while it springs between sizes.
            .clipShape(shape)
            .offset(x: frame.minX, y: frame.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Self.spring, value: state.phase)
            .animation(Self.spring, value: state.showsWings)
            .animation(Self.spring, value: state.anchor)
    }

    @ViewBuilder
    private func content(atNotch: Bool) -> some View {
        switch state.phase {
        case .expanded:
            ExpandedContent(
                info: state.nowPlaying, topInset: atNotch ? geometry.notch.height : 8,
                onCommand: onCommand)
                .transition(.opacity)
        case .collapsed, .stretching, .detached, .settling:
            if atNotch {
                if state.showsWings, let info = state.nowPlaying {
                    CollapsedContent(info: info, notchWidth: geometry.notch.width)
                        .transition(.opacity)
                }
            } else {
                FloatingCollapsedContent(info: state.nowPlaying)
                    .transition(.opacity)
            }
        }
    }
}
