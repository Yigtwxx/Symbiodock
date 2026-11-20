import Testing
@testable import SymbiodockCore

struct IslandTabTests {
    @Test func defaultOrderPutsAgentsFirst() {
        #expect(TabOrder.default == [.agents, .media, .files])
    }

    @Test func repairKeepsAValidOrder() {
        #expect(TabOrder.repaired(["media", "agents"]) == [.media, .agents, .files])
    }

    @Test func repairFillsWhatIsMissing() {
        #expect(TabOrder.repaired(nil) == [.agents, .media, .files])
        #expect(TabOrder.repaired([]) == [.agents, .media, .files])
        #expect(TabOrder.repaired(["media"]) == [.media, .agents, .files])
    }

    @Test func repairDropsUnknownAndRepeatedValues() {
        #expect(TabOrder.repaired(["weather", "media", "media", "agents"]) == [.media, .agents, .files])
    }

    @Test func movingToTheFrontKeepsTheRest() {
        #expect(TabOrder.moving(.media, toFrontOf: [.agents, .media]) == [.media, .agents, .files])
        #expect(TabOrder.moving(.agents, toFrontOf: [.agents, .media]) == [.agents, .media, .files])
    }

    @Test func encodingRoundTrips() {
        #expect(TabOrder.repaired(TabOrder.encode([.media, .agents])) == [.media, .agents, .files])
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
                    mediaHasFace: false, agentsHasFace: false,
                    mediaHasContent: true, agentsHasContent: true, filesHasContent: false) == .agents)
        }
    }

    @Test func otherwiseTheFirstTabWithContentOpens() {
        let mediaFirst: [IslandTab] = [.media, .agents]
        let agentsFirst: [IslandTab] = [.agents, .media]
        #expect(
            TabSelection.tabToOpen(
                order: mediaFirst, attention: .none,
                mediaHasFace: false, agentsHasFace: false,
                mediaHasContent: true, agentsHasContent: true, filesHasContent: false) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: agentsFirst, attention: .none,
                mediaHasFace: false, agentsHasFace: false,
                mediaHasContent: true, agentsHasContent: false, filesHasContent: false) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: mediaFirst, attention: .none,
                mediaHasFace: false, agentsHasFace: false,
                mediaHasContent: false, agentsHasContent: false, filesHasContent: false) == .media)
        #expect(
            TabSelection.tabToOpen(
                order: agentsFirst, attention: .none,
                mediaHasFace: false, agentsHasFace: false,
                mediaHasContent: false, agentsHasContent: false, filesHasContent: false) == .agents)
    }

    @Test func anActiveTabOpensBeforeOneThatOnlyHasContent() {
        func open(_ order: [IslandTab], mediaFace: Bool, agentsFace: Bool) -> IslandTab {
            TabSelection.tabToOpen(
                order: order, attention: .none,
                mediaHasFace: mediaFace, agentsHasFace: agentsFace,
                mediaHasContent: true, agentsHasContent: true, filesHasContent: true)
        }
        let agentsFirst: [IslandTab] = [.agents, .media, .files]
        let mediaFirst: [IslandTab] = [.media, .agents, .files]
        // An idle agent is still listed, but playing music is what is going on.
        #expect(open(agentsFirst, mediaFace: true, agentsFace: false) == .media)
        // The agent works again: back to the first tab.
        #expect(open(agentsFirst, mediaFace: true, agentsFace: true) == .agents)
        #expect(open(mediaFirst, mediaFace: false, agentsFace: true) == .agents)
        #expect(open(mediaFirst, mediaFace: true, agentsFace: true) == .media)
        // Nothing going on: the first tab with content, as before.
        #expect(open(agentsFirst, mediaFace: false, agentsFace: false) == .agents)
        #expect(open(mediaFirst, mediaFace: false, agentsFace: false) == .media)
    }

    @Test func theBubbleTakesTheSecondTabWhenBothHaveAFace() {
        let agentsFirst: [IslandTab] = [.agents, .media]
        let mediaFirst: [IslandTab] = [.media, .agents]
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: true, agentsHasFace: true) == .media)
        #expect(TabSelection.bubble(order: mediaFirst, mediaHasFace: true, agentsHasFace: true) == .agents)
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: true, agentsHasFace: false) == nil)
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: false, agentsHasFace: true) == nil)
        #expect(TabSelection.bubble(order: agentsFirst, mediaHasFace: false, agentsHasFace: false) == nil)
    }

    @Test func filesIsAlwaysTheLastTab() {
        #expect(TabOrder.default == [.agents, .media, .files])
        #expect(TabOrder.repaired(nil) == [.agents, .media, .files])
        #expect(TabOrder.repaired(["media", "agents"]) == [.media, .agents, .files])
        #expect(TabOrder.repaired(["files", "media"]) == [.media, .agents, .files])
    }

    @Test func filesCannotBeMovedToTheFront() {
        #expect(TabOrder.reorderable == [.agents, .media])
        #expect(TabOrder.moving(.files, toFrontOf: [.media, .agents, .files]) == [.media, .agents, .files])
        #expect(TabOrder.moving(.media, toFrontOf: TabOrder.default) == [.media, .agents, .files])
    }

    @Test func filesOpensOnlyWhenNothingElseHasContent() {
        func open(_ attention: AgentAttention, media: Bool, agents: Bool, files: Bool) -> IslandTab {
            TabSelection.tabToOpen(
                order: TabOrder.default, attention: attention,
                mediaHasFace: false, agentsHasFace: false,
                mediaHasContent: media, agentsHasContent: agents, filesHasContent: files)
        }
        #expect(open(.none, media: false, agents: false, files: true) == .files)
        #expect(open(.none, media: true, agents: false, files: true) == .media)
        #expect(open(.needsInput, media: false, agents: false, files: true) == .agents)
        #expect(open(.none, media: false, agents: false, files: false) == .agents)
    }

    @Test func filesNeverHasAFaceOrTheLeftBubble() {
        #expect(TabSelection.face(order: TabOrder.default, mediaHasFace: false, agentsHasFace: false) == .none)
        #expect(TabSelection.bubble(order: TabOrder.default, mediaHasFace: true, agentsHasFace: true) == .media)
    }
}
