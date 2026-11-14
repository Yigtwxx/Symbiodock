import SwiftUI
import SymbiodockCore

/// The tab buttons of the expanded island, in the user's order.
struct TabStrip: View {
    let order: [IslandTab]
    let selected: IslandTab
    let attention: AgentAttention
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
                .accessibilityAddTraits(tab == selected ? .isSelected : [])
            }
        }
    }

    private func glyph(_ tab: IslandTab) -> some View {
        VStack(spacing: 2) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                    // The agents want attention while another tab is looked at.
                    if tab == .agents, selected != .agents, attention != .none {
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
    var symbol: String {
        switch self {
        case .agents: "sparkles"
        case .media: "music.note"
        }
    }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .media: "Media"
        }
    }
}
