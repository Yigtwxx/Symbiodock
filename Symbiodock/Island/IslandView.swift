import SwiftUI
import SymbiodockCore

struct IslandView: View {
    let state: IslandState
    let geometry: IslandGeometry
    let session: DragSession
    let onCommand: (PlaybackCommand) -> Void
    let onOpenSession: (AgentSession) -> Void

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
            showsWings: state.showsWings)
        // Wherever it rests, the island sits against its screen edge the way the notch does:
        // square on that edge, rounded on the free side.
        let radii = IslandLayout.cornerRadii(
            anchor: state.anchor,
            radius: state.phase == .expanded
                ? IslandLayout.expandedCornerRadius : IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)

        return shape
            .fill(.black)
            .overlay { content(atNotch: atNotch, frame: frame) }
            .overlay {
                if state.phase == .collapsed {
                    RimLight(
                        attention: state.board.attention, radii: radii,
                        dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor),
                        isVertical: IslandLayout.isSideDocked(state.anchor))
                }
            }
            .overlay {
                if state.showsCompactingRim {
                    CompactingRim(
                        radii: radii, dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor))
                }
            }
            .frame(width: frame.width, height: frame.height)
            // Content must not draw outside the shape while it springs between sizes.
            .clipShape(shape)
            .offset(x: frame.minX, y: frame.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Self.spring, value: state.phase)
            .animation(Self.spring, value: state.showsWings)
            .animation(Self.spring, value: state.anchor)
            .animation(Self.spring, value: state.face)
    }

    @ViewBuilder
    private func content(atNotch: Bool, frame: CGRect) -> some View {
        switch state.phase {
        case .expanded:
            ExpandedIsland(
                state: state, metrics: headerMetrics(atNotch: atNotch, frame: frame),
                onCommand: onCommand, onOpenSession: onOpenSession)
                .transition(.opacity)
        case .collapsed, .stretching, .detached, .settling:
            collapsedFace(atNotch: atNotch)
                .transition(.opacity)
        }
    }

    /// The collapsed island shows one face: the first tab's if it has one, else the other's.
    @ViewBuilder
    private func collapsedFace(atNotch: Bool) -> some View {
        let lead = state.board.lead
        // On the media face an agent that wants attention still gets its mark.
        let attention = state.board.attentionRow?.state
        // A docked island never hides: with no face it shows the paused track if there is
        // one, otherwise the first tab's idle text. When the agents speak without a lead
        // (all idle or merely running) it shows the first session of the list; the idle
        // text is for an empty list only.
        let agentsSpeak = state.face == .agents
            || (state.face == .none && state.nowPlaying == nil && state.tabOrder.first == .agents)

        if atNotch {
            switch state.face {
            case .agents:
                if let lead {
                    AgentNotchFace(row: lead, notchWidth: geometry.notch.width)
                        // Centred on the notch, not on the strip below it.
                        .padding(.bottom, IslandLayout.notchLip)
                }
            case .media:
                if let info = state.nowPlaying {
                    CollapsedContent(
                        info: info, notchWidth: geometry.notch.width, attention: attention)
                        .padding(.bottom, IslandLayout.notchLip)
                }
            case .none:
                EmptyView()
            }
        } else if IslandLayout.isSideDocked(state.anchor) {
            if agentsSpeak {
                AgentSideFace(row: state.board.spokesperson)
            } else {
                SideCollapsedContent(info: state.nowPlaying, attention: attention)
            }
        } else {
            if agentsSpeak {
                AgentFloatingFace(row: state.board.spokesperson)
            } else {
                FloatingCollapsedContent(info: state.nowPlaying, attention: attention)
            }
        }
    }

    /// At the notch the header shares its band with the camera housing; elsewhere it has
    /// a band of its own, split down the middle.
    private func headerMetrics(atNotch: Bool, frame: CGRect) -> ExpandedHeaderMetrics {
        guard atNotch else {
            return ExpandedHeaderMetrics(
                height: ExpandedIsland.dockedBandHeight,
                leading: frame.width / 2, gap: 0, trailing: frame.width / 2)
        }
        let notch = geometry.notch
        return ExpandedHeaderMetrics(
            height: notch.height,
            leading: max(notch.minX - frame.minX, 0),
            gap: notch.width,
            trailing: max(frame.maxX - notch.maxX, 0))
    }
}
