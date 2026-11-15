import SwiftUI
import SymbiodockCore

/// Where the header's parts go. At the notch the camera housing sits in the middle of the
/// band, so the tab strip is left of it and the summary right of it.
struct ExpandedHeaderMetrics: Equatable {
    var height: CGFloat
    var leading: CGFloat
    /// Width hidden by the camera housing; 0 away from the notch.
    var gap: CGFloat
    var trailing: CGFloat
}

/// The open island: a header band with the tabs, and the selected tab below it.
struct ExpandedIsland: View {
    /// Height of the header band where there is no notch to give it one.
    static let dockedBandHeight: CGFloat = 26

    let state: IslandState
    let metrics: ExpandedHeaderMetrics
    let onCommand: (PlaybackCommand) -> Void
    let onOpenSession: (AgentSession) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch state.selectedTab {
                case .media:
                    ExpandedContent(
                        info: state.nowPlaying, topInset: metrics.height, onCommand: onCommand)
                case .agents:
                    AgentsContent(
                        rows: state.board.rows, topInset: metrics.height, onOpen: onOpenSession)
                }
            }
            .transition(.opacity)
            header
        }
        .animation(.easeOut(duration: 0.15), value: state.selectedTab)
    }

    private var header: some View {
        HStack(spacing: 0) {
            TabStrip(
                order: state.tabOrder, selected: state.selectedTab,
                attention: state.board.attention,
                hasUnseenFinish: state.board.hasUnseenFinish
            ) { tab in
                state.selectTab(tab)
            }
            .padding(.leading, 14)
            .frame(width: metrics.leading, alignment: .leading)

            Color.clear.frame(width: metrics.gap)

            // The summary can be absent; the column keeps its width regardless.
            Color.clear
                .frame(width: metrics.trailing)
                .overlay(alignment: .trailing) {
                    summary.padding(.trailing, 14)
                }
        }
        .frame(height: metrics.height)
    }

    @ViewBuilder
    private var summary: some View {
        if state.selectedTab == .agents,
           let text = AgentLabels.summary(
               needsInput: state.board.needsInputCount, working: state.board.workingCount) {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
