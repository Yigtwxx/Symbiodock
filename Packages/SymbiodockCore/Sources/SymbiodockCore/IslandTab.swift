import Foundation

/// The pages of the expanded island.
public enum IslandTab: String, CaseIterable, Sendable {
    case agents
    case media
}

/// The order of the tabs, as the user chose it. Stored as raw values.
public enum TabOrder {
    public static let `default`: [IslandTab] = [.agents, .media]

    /// Makes any stored list hold every tab exactly once: unknown and repeated values are
    /// dropped, missing tabs are appended in default order.
    public static func repaired(_ raw: [String]?) -> [IslandTab] {
        var order: [IslandTab] = []
        for value in raw ?? [] {
            if let tab = IslandTab(rawValue: value), !order.contains(tab) { order.append(tab) }
        }
        for tab in `default` where !order.contains(tab) { order.append(tab) }
        return order
    }

    public static func moving(_ tab: IslandTab, toFrontOf order: [IslandTab]) -> [IslandTab] {
        repaired(([tab] + order.filter { $0 != tab }).map(\.rawValue))
    }

    public static func encode(_ order: [IslandTab]) -> [String] {
        order.map(\.rawValue)
    }
}

/// What the collapsed island shows.
public enum IslandFace: Equatable, Sendable {
    case none
    case media
    case agents
}

public enum TabSelection {
    /// The first tab in order that has a face; `.none` if neither has.
    public static func face(
        order: [IslandTab], mediaHasFace: Bool, agentsHasFace: Bool
    ) -> IslandFace {
        for tab in order {
            switch tab {
            case .media where mediaHasFace: return .media
            case .agents where agentsHasFace: return .agents
            default: continue
            }
        }
        return .none
    }

    /// The tab whose face moves out to the bubble beside the island: the second in order,
    /// while both have a face. Nil while at most one has.
    public static func bubble(
        order: [IslandTab], mediaHasFace: Bool, agentsHasFace: Bool
    ) -> IslandTab? {
        guard mediaHasFace, agentsHasFace else { return nil }
        switch face(order: order, mediaHasFace: true, agentsHasFace: true) {
        case .agents: return .media
        case .media: return .agents
        case .none: return nil
        }
    }

    /// The tab the island opens on. Attention wins; then the first tab with something to
    /// show; then simply the first tab.
    public static func tabToOpen(
        order: [IslandTab], attention: AgentAttention,
        mediaHasContent: Bool, agentsHasContent: Bool
    ) -> IslandTab {
        if attention != .none { return .agents }
        for tab in order {
            switch tab {
            case .media where mediaHasContent: return .media
            case .agents where agentsHasContent: return .agents
            default: continue
            }
        }
        return order.first ?? TabOrder.default[0]
    }
}
