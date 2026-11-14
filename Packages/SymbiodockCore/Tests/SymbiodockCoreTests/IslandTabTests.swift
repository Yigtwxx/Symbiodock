import Testing
@testable import SymbiodockCore

struct IslandTabTests {
    @Test func defaultOrderPutsAgentsFirst() {
        #expect(TabOrder.default == [.agents, .media])
    }

    @Test func repairKeepsAValidOrder() {
        #expect(TabOrder.repaired(["media", "agents"]) == [.media, .agents])
    }

    @Test func repairFillsWhatIsMissing() {
        #expect(TabOrder.repaired(nil) == [.agents, .media])
        #expect(TabOrder.repaired([]) == [.agents, .media])
        #expect(TabOrder.repaired(["media"]) == [.media, .agents])
    }

    @Test func repairDropsUnknownAndRepeatedValues() {
        #expect(TabOrder.repaired(["weather", "media", "media", "agents"]) == [.media, .agents])
    }

    @Test func movingToTheFrontKeepsTheRest() {
        #expect(TabOrder.moving(.media, toFrontOf: [.agents, .media]) == [.media, .agents])
        #expect(TabOrder.moving(.agents, toFrontOf: [.agents, .media]) == [.agents, .media])
    }

    @Test func encodingRoundTrips() {
        #expect(TabOrder.repaired(TabOrder.encode([.media, .agents])) == [.media, .agents])
    }

    @Test func theFaceIsTheFirstTabThatHasOne() {
        let agentsFirst: [IslandTab] = [.agents, .media]
        let mediaFirst: [IslandTab] = [.media, .agents]
        #expect(TabSelection.face(order: agentsFirst, mediaHasFace: true, agentsHasFace: true) == .agents)
        #expect(TabSelection.face(order: mediaFirst, mediaHasFace: true, agentsHasFace: true) == .media)
        #expect(TabSelection.face(order: agentsFirst, mediaHasFace: true, agentsHasFace: false) == .media)
        #expect(TabSelection.face(order: mediaFirst, mediaHasFace: false, agentsHasFace: true) == .agents)
        #expect(TabSelection.face(order: agentsFirst, mediaHasFace: false, agentsHasFace: false) == .none)
    }

    @Test func attentionOpensTheAgentsTab() {
        for attention in [AgentAttention.needsInput, .finished] {
            #expect(
                TabSelection.tabToOpen(
                    order: [.media, .agents], attention: attention,
                    mediaHasContent: true, agentsHasContent: true) == .agents)
        }
    }

    @Test func otherwiseTheFirstTabWithContentOpens() {
        let mediaFirst: [IslandTab] = [.media, .agents]
        let agentsFirst: [IslandTab] = [.agents, .media]
        #expect(
            TabSelection.tabToOpen(
                order: mediaFirst, attention: .none,
                mediaHasContent: true, agentsHasContent: true) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: agentsFirst, attention: .none,
                mediaHasContent: true, agentsHasContent: false) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: mediaFirst, attention: .none,
                mediaHasContent: false, agentsHasContent: false) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: agentsFirst, attention: .none,
                mediaHasContent: false, agentsHasContent: false) == .agents)
    }
}
