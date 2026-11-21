import SwiftUI
import SymbiodockCore

/// The tab buttons of the expanded island, in the user's order.
struct TabStrip: View {
    let order: [IslandTab]
    let selected: IslandTab
    let attention: AgentAttention
    /// A finish the user has not looked at yet, even after its effect ended.
    var hasUnseenFinish = false
    let onSelect: (IslandTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(order, id: \.self) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    glyph(tab)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(pipText(for: tab))
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
    }

    /// Whether the pip is showing on this tab's glyph: the agents want attention, or hold
    /// a finish not seen yet, while another tab is looked at.
    private func showsPip(_ tab: IslandTab) -> Bool {
        tab == .agents && selected != .agents && (attention != .none || hasUnseenFinish)
    }

    /// What the pip says, for VoiceOver; empty while there is no pip.
    private func pipText(for tab: IslandTab) -> String {
        guard showsPip(tab) else { return "" }
        return attention == .needsInput ? "Needs input" : "Finished"
    }

    private func glyph(_ tab: IslandTab) -> some View {
        VStack(spacing: 2) {
            TabGlyph(tab: tab)
                .overlay(alignment: .topTrailing) {
                    // The agents want attention while another tab is looked at.
                    if showsPip(tab) {
                        Circle()
                            .fill(attention == .needsInput ? AgentPalette.alert : AgentPalette.mint)
                            .frame(width: 5, height: 5)
                            .offset(x: 4, y: -3)
                    }
                }
            Circle()
                .fill(.white)
                .frame(width: 3, height: 3)
                .opacity(tab == selected ? 1 : 0)
        }
        .foregroundStyle(.white.opacity(tab == selected ? 1 : 0.4))
        .frame(width: 28, height: 22)
        .contentShape(Rectangle())
    }
}

extension IslandTab {
    var title: String {
        switch self {
        case .agents: "Agents"
        case .media: "Media"
        case .system: "System"
        case .files: "Files"
        }
    }
}
