import CoreGraphics
import Foundation
import Testing
@testable import SymbiodockCore

@MainActor
struct IslandStateTests {
    @Test func startsCollapsed() {
        #expect(IslandState().phase == .collapsed)
    }

    @Test func hoveringExpandsAndLeavingCollapses() {
        let state = IslandState()

        state.setHovering(true)
        #expect(state.phase == .expanded)

        state.setHovering(false)
        #expect(state.phase == .collapsed)
    }

    @Test func hoverTimingMatchesTheSpec() {
        #expect(HoverTiming.enterDelay == .milliseconds(80))
        #expect(HoverTiming.exitDelay == .milliseconds(250))
    }

    private func track(playing: Bool) -> NowPlayingInfo {
        NowPlayingInfo(title: "T", artist: "A", isPlaying: playing, sourceName: "Music")
    }

    @Test func mirrorsTheCurrentTrack() {
        let state = IslandState()
        #expect(state.nowPlaying == nil)

        state.setNowPlaying(track(playing: true))
        #expect(state.nowPlaying == track(playing: true))

        state.setNowPlaying(nil)
        #expect(state.nowPlaying == nil)
    }

    @Test func wingsShowWhilePlayingAndHideWhenTheTrackGoesAway() {
        let state = IslandState()
        #expect(!state.showsWings)

        state.setNowPlaying(track(playing: true))
        #expect(state.showsWings)

        state.setNowPlaying(nil)
        #expect(!state.showsWings)
    }

    @Test func wingsOutliveAPauseUntilTheGraceElapses() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))

        state.setNowPlaying(track(playing: false))
        #expect(state.showsWings)

        state.pausedGraceElapsed()
        #expect(!state.showsWings)
        #expect(state.nowPlaying != nil)
    }

    @Test func resumingBeforeTheGraceElapsesKeepsTheWings() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))
        state.setNowPlaying(track(playing: false))
        state.setNowPlaying(track(playing: true))

        state.pausedGraceElapsed()
        #expect(state.showsWings)
    }

    @Test func aTrackThatWasAlreadyPausedNeverShowsWings() {
        let state = IslandState()
        state.setNowPlaying(track(playing: false))
        #expect(!state.showsWings)
    }

    @Test func pausedGraceIsTenSeconds() {
        #expect(WingsTiming.pausedGrace == .seconds(10))
    }

    // MARK: Dragging

    let origin = CGPoint(x: 756, y: 16)

    private func stretching(from expanded: Bool = false) -> IslandState {
        let state = IslandState()
        if expanded { state.setHovering(true) }
        state.beginDrag(at: origin, from: origin)
        return state
    }

    private func detached() -> IslandState {
        let state = stretching()
        state.drag(to: CGPoint(x: 756, y: 137))
        return state
    }

    @Test func startsAtTheNotchAndNotDragging() {
        let state = IslandState()
        #expect(state.anchor == .notch)
        #expect(!state.isDragging)
        #expect(state.dragLocation == nil)
    }

    @Test func dragBeginsFromCollapsedAndFromExpanded() {
        for expanded in [false, true] {
            let state = stretching(from: expanded)
            #expect(state.phase == .stretching)
            #expect(state.dragLocation == origin)
            #expect(state.dragOrigin == origin)
        }
    }

    @Test func pullingPastTheTearDistanceDetachesOnce() {
        let state = stretching()

        #expect(state.drag(to: CGPoint(x: 756, y: 136)) == false)
        #expect(state.phase == .stretching)
        #expect(state.drag(to: CGPoint(x: 756, y: 137)) == true)
        #expect(state.phase == .detached)
        #expect(state.drag(to: CGPoint(x: 756, y: 300)) == false)
        #expect(state.phase == .detached)
    }

    @Test func detachedIslandDoesNotReattachDuringTheDrag() {
        let state = detached()
        state.drag(to: origin)
        #expect(state.phase == .detached)
    }

    @Test func releasingWhileAttachedSnapsBackToTheSameAnchor() {
        let state = stretching()
        state.endDrag(resolvedAnchor: .corner(.topLeft))

        #expect(state.phase == .settling)
        #expect(state.anchor == .notch)
        #expect(state.dragLocation == nil)
    }

    @Test func releasingWhileDetachedMovesToTheResolvedAnchor() {
        let state = detached()
        state.endDrag(resolvedAnchor: .corner(.topLeft))
        #expect(state.phase == .settling)

        state.finishSettling()
        #expect(state.phase == .collapsed)
        #expect(state.anchor == .corner(.topLeft))
    }

    @Test func hoverIsIgnoredWhileDraggingAndSettling() {
        let state = stretching()
        state.setHovering(true)
        #expect(state.phase == .stretching)

        state.drag(to: CGPoint(x: 756, y: 300))
        state.setHovering(false)
        #expect(state.phase == .detached)

        state.endDrag(resolvedAnchor: .notch)
        state.setHovering(true)
        #expect(state.phase == .settling)
    }

    @Test func eventsOutOfOrderAreIgnored() {
        let state = IslandState()
        #expect(state.drag(to: CGPoint(x: 0, y: 500)) == false)
        state.endDrag(resolvedAnchor: .corner(.topLeft))
        state.finishSettling()
        #expect(state.phase == .collapsed)
        #expect(state.anchor == .notch)
        #expect(state.dragLocation == nil)

        state.beginDrag(at: origin, from: origin)
        state.beginDrag(at: CGPoint(x: 5, y: 5), from: CGPoint(x: 1, y: 1))
        #expect(state.phase == .stretching)
        #expect(state.dragOrigin == origin)
        #expect(state.dragLocation == origin)
    }

    @Test func restoreAnchorAppliesOnlyWhenIdle() {
        let state = IslandState()
        state.restoreAnchor(.edge(.left, fraction: 0.5))
        #expect(state.anchor == .edge(.left, fraction: 0.5))

        state.beginDrag(at: origin, from: origin)
        state.restoreAnchor(.corner(.bottomRight))
        #expect(state.anchor == .edge(.left, fraction: 0.5))
    }

    // MARK: Tear metric

    @Test func tearIsMeasuredFromWhereTheGrabStarted() {
        let state = IslandState()
        state.setHovering(true)
        state.beginDrag(at: CGPoint(x: 900, y: 120), from: origin)

        #expect(state.drag(to: CGPoint(x: 901, y: 120)) == false)
        #expect(state.phase == .stretching)
        #expect(state.drag(to: CGPoint(x: 900, y: 240)) == false)
        #expect(state.drag(to: CGPoint(x: 900, y: 241)) == true)
        #expect(state.phase == .detached)
    }

    @Test func dragOffsetIsThePointerMovementSinceTheGrab() {
        let state = IslandState()
        #expect(state.dragOffset == nil)

        state.beginDrag(at: CGPoint(x: 900, y: 120), from: origin)
        #expect(state.dragStart == CGPoint(x: 900, y: 120))
        #expect(state.dragOffset == CGSize(width: 0, height: 0))

        state.drag(to: CGPoint(x: 910, y: 100))
        #expect(state.dragOffset == CGSize(width: 10, height: -20))

        state.endDrag(resolvedAnchor: .notch)
        #expect(state.dragOffset == nil)
        #expect(state.dragStart == nil)
    }

    @Test func tearDistanceIsSharedWithTheSimulation() {
        #expect(IslandState.tearDistance == IslandDrag.tearDistance)
        #expect(SymbioteSimulation.Configuration().tearDistance == IslandDrag.tearDistance)
    }

    // MARK: Cancelling

    @Test func cancelDragReturnsToCollapsedFromEveryDragPhase() {
        let phases: [(String, IslandState)] = [
            ("stretching", stretching()),
            ("detached", detached()),
            ("settling", {
                let state = detached()
                state.endDrag(resolvedAnchor: .corner(.topLeft))
                return state
            }()),
        ]
        for (name, state) in phases {
            let anchorBefore = state.anchor
            state.cancelDrag()
            #expect(state.phase == .collapsed, "\(name)")
            #expect(state.anchor == anchorBefore, "\(name)")
            #expect(state.dragLocation == nil, "\(name)")
            #expect(state.dragStart == nil, "\(name)")
            #expect(state.dragOrigin == nil, "\(name)")
        }
    }

    @Test func cancelDragDoesNothingWhenIdle() {
        let collapsed = IslandState()
        collapsed.cancelDrag()
        #expect(collapsed.phase == .collapsed)

        let expanded = IslandState()
        expanded.setHovering(true)
        expanded.cancelDrag()
        #expect(expanded.phase == .expanded)
    }

    // MARK: Ignored transitions

    private func settling() -> IslandState {
        let state = detached()
        state.endDrag(resolvedAnchor: .corner(.topLeft))
        return state
    }

    @Test func beginDragAndRestoreAnchorAreIgnoredWhileDetachedAndSettling() {
        for state in [detached(), settling()] {
            let phase = state.phase
            let anchor = state.anchor
            let dragOrigin = state.dragOrigin
            state.beginDrag(at: CGPoint(x: 5, y: 5), from: CGPoint(x: 1, y: 1))
            state.restoreAnchor(.corner(.bottomRight))
            #expect(state.phase == phase)
            #expect(state.anchor == anchor)
            #expect(state.dragOrigin == dragOrigin)
        }
    }

    @Test func endDragIsIgnoredWhileSettling() {
        let state = settling()
        state.endDrag(resolvedAnchor: .corner(.bottomRight))
        #expect(state.phase == .settling)
        state.finishSettling()
        #expect(state.anchor == .corner(.topLeft))
    }

    @Test func finishSettlingIsIgnoredWhileStretching() {
        let state = stretching()
        state.finishSettling()
        #expect(state.phase == .stretching)
    }

    @Test func settlingAFinishClosesTheWings() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.sealingID == "a")
        #expect(state.showsWings)
        state.settleFinished("a")
        #expect(state.sealingID == nil)
        #expect(!state.showsWings)
        #expect(state.board.rows.first?.state == .finished)
    }

    @Test func noSealPlaysWhileTheIslandIsOpen() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(true)
        #expect(state.sealingID == nil)
    }

    @Test func theMediaFaceAlsoSealsAFinish() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.face == .media)
        #expect(state.sealingID == "a")
    }

    @Test func theCompactingRimShowsWhileTheAgentsFaceCompacts() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .compacting)])
        #expect(state.showsCompactingRim)
        state.setHovering(true)
        #expect(!state.showsCompactingRim)
        state.setHovering(false)
        state.setAgentSessions([agent("a", .idle)])
        #expect(!state.showsCompactingRim)
    }

    @Test func theCompactingRimWaitsBehindAFinish() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working), agent("b", .compacting)])
        state.setAgentSessions([agent("a", .idle), agent("b", .compacting)])
        #expect(!state.showsCompactingRim)
        state.settleFinished("a")
        #expect(state.showsCompactingRim)
    }

    @Test func theMediaFaceShowsNoCompactingRim() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .compacting)])
        #expect(state.face == .media)
        #expect(!state.showsCompactingRim)
    }

    @Test func theWorkingAuroraShowsWhileTheAgentsFaceWorks() {
        let state = IslandState()
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.showsWorkingAurora)
        state.setHovering(true)
        #expect(!state.showsWorkingAurora)
        state.setHovering(false)
        #expect(state.showsWorkingAurora)
    }

    @Test func theWorkingAuroraIsOnlyForWork() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .compacting)])
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .running)])
        #expect(!state.showsWorkingAurora)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.showsWorkingAurora)
        // It has finished: the seal plays and the light turns mint with it.
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.showsWorkingAurora)
        #expect(state.auroraIsFinishing)
        state.settleFinished("a")
        #expect(!state.showsWorkingAurora)
        #expect(!state.auroraIsFinishing)
    }

    @Test func theLightIsNotFinishingWhileItsSessionWorks() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        #expect(state.showsWorkingAurora)
        #expect(!state.auroraIsFinishing)
    }

    @Test func aFinishOnTheMediaFaceHasNoLight() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.face == .media)
        #expect(!state.showsWorkingAurora)
        #expect(!state.auroraIsFinishing)
    }

    @Test func aFinishWhileOpenLightsWhenTheIslandCloses() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        // Opened on another tab: leaving the Agents tab would count the finish as seen.
        state.setHovering(true, opening: .media)
        state.setAgentSessions([agent("a", .idle)])
        #expect(!state.showsWorkingAurora)
        #expect(!state.auroraIsFinishing)
        state.setHovering(false)
        #expect(state.showsWorkingAurora)
        #expect(state.auroraIsFinishing)
    }

    @Test func theWorkingAuroraTurnsMintForAFinishThenFollowsTheNextLead() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working), agent("b", .working)])
        state.setAgentSessions([agent("a", .idle), agent("b", .working)])
        #expect(state.showsWorkingAurora)
        #expect(state.auroraIsFinishing)
        state.settleFinished("a")
        #expect(state.showsWorkingAurora)
        #expect(!state.auroraIsFinishing)
        state.setAgentSessions([agent("a", .idle), agent("b", .working), agent("c", .needsInput(prompt: nil))])
        #expect(!state.showsWorkingAurora)
        #expect(!state.auroraIsFinishing)
    }

    @Test func theWorkingAuroraDoesNotShowWhileTheIslandIsDragged() {
        let state = stretching()
        state.setAgentSessions([agent("a", .working)])
        #expect(state.phase == .stretching)
        #expect(!state.showsWorkingAurora)
    }

    @Test func theMediaFaceShowsNoWorkingAurora() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        #expect(state.face == .media)
        #expect(!state.showsWorkingAurora)
    }

    private func agent(_ id: String, _ activity: AgentActivity) -> AgentSession {
        AgentSession(
            id: id, tool: .claudeCode, title: id, projectPath: nil, activity: activity,
            since: Date(timeIntervalSince1970: 0), pid: nil)
    }

    @Test func aWorkingAgentWidensTheIsland() {
        let state = IslandState()
        #expect(!state.showsWings)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.showsWings)
        #expect(state.face == .agents)
        state.setAgentSessions([])
        #expect(!state.showsWings)
        #expect(state.face == .none)
    }

    @Test func theFaceFollowsTheTabOrder() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        #expect(state.face == .agents)
        state.setTabOrder([.media, .agents])
        #expect(state.face == .media)
        #expect(state.tabOrder == [.media, .agents, .files])
    }

    @Test func hoverOpensTheFirstTabWithContent() {
        let state = IslandState()
        state.setTabOrder([.agents, .media])
        state.setNowPlaying(track(playing: true))
        state.setHovering(true)
        #expect(state.selectedTab == .media)
    }

    @Test func hoverOpensAgentsWhenOneNeedsInput() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        state.setHovering(true)
        #expect(state.selectedTab == .agents)
    }

    @Test func hoverOpensMediaWhileTheAgentIsIdleAndAgentsOnceItWorks() {
        let state = IslandState()
        state.setTabOrder([.agents, .media])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(true)
        #expect(state.selectedTab == .media)
        state.setHovering(false)

        state.setAgentSessions([agent("a", .working)])
        state.setHovering(true)
        #expect(state.selectedTab == .agents)
        state.setHovering(false)
    }

    @Test func aFinishKeepsAgentsUntilItsSealHasPlayed() {
        let state = IslandState()
        state.setTabOrder([.agents, .media])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(TabSelection.tabToOpen(
            order: state.tabOrder, attention: state.board.attention,
            mediaHasFace: state.mediaWings, agentsHasFace: state.board.hasFace,
            mediaHasContent: true, agentsHasContent: true, filesHasContent: false) == .agents)

        state.settleFinished("a")
        state.setHovering(true)
        #expect(state.selectedTab == .media)
    }

    @Test func pausedMusicStopsCountingAfterItsGrace() {
        let state = IslandState()
        state.setTabOrder([.agents, .media])
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .idle)])
        state.setNowPlaying(track(playing: false))
        state.setHovering(true)
        #expect(state.selectedTab == .media)
        state.setHovering(false)

        state.pausedGraceElapsed()
        state.setHovering(true)
        #expect(state.selectedTab == .agents)
    }

    @Test func aClickChangesTheTabAndNewSessionsDoNot() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setHovering(true)
        #expect(state.selectedTab == .media)
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        #expect(state.selectedTab == .media)
        state.selectTab(.agents)
        #expect(state.selectedTab == .agents)
    }

    @Test func leavingTheAgentsTabClearsFinishedMarks() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        #expect(state.board.attention == .finished)

        state.setHovering(true)
        #expect(state.selectedTab == .agents)
        // Still marked while it is being looked at.
        #expect(state.board.attention == .finished)

        state.setHovering(false)
        #expect(state.board.attention == .none)
        #expect(!state.showsWings)
    }

    @Test func switchingAwayFromAgentsAlsoClearsFinishedMarks() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(true)
        state.selectTab(.media)
        #expect(state.board.attention == .none)
    }

    @Test func collapsingFromTheMediaTabKeepsFinishedMarks() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setNowPlaying(track(playing: true))
        state.setHovering(true)
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(false)
        #expect(state.board.attention == .finished)
    }

    @Test func aDamagedTabOrderIsRepaired() {
        let state = IslandState()
        state.setTabOrder([.media])
        #expect(state.tabOrder == [.media, .agents, .files])
    }

    @Test func startingADragFromTheExpandedAgentsTabClearsFinishedMarks() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(true)
        #expect(state.selectedTab == .agents)
        #expect(state.board.attention == .finished)
        state.beginDrag(at: .zero, from: .zero)
        #expect(state.board.attention == .none)
    }

    @Test func anIdenticalSessionListLeavesTheBoardEqual() {
        let state = IslandState()
        let sessions = [agent("a", .working), agent("b", .needsInput(prompt: "ok?"))]
        state.setAgentSessions(sessions)
        let before = state.board
        state.setAgentSessions(sessions)
        #expect(state.board == before)
    }

    @Test func theSameTabOrderInGivesTheSameOrderOut() {
        let state = IslandState()
        state.setTabOrder([.agents, .media])
        state.setTabOrder([.agents, .media])
        #expect(state.tabOrder == [.agents, .media, .files])
    }

    @Test func theBubbleHoldsTheSecondFaceAtTheCollapsedNotch() {
        let state = IslandState()
        #expect(state.bubbleTab == nil)
        state.setNowPlaying(track(playing: true))
        #expect(state.bubbleTab == nil)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.face == .agents)
        #expect(state.bubbleTab == .media)
        state.setTabOrder([.media, .agents])
        #expect(state.face == .media)
        #expect(state.bubbleTab == .agents)
    }

    @Test func theBubbleGoesWhileTheIslandIsOpenOrAwayFromTheNotch() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .working)])
        state.setHovering(true)
        #expect(state.bubbleTab == nil)
        state.setHovering(false)
        #expect(state.bubbleTab == .media)
        state.restoreAnchor(.edge(.bottom, fraction: 0.5))
        #expect(state.bubbleTab == nil)
    }

    @Test func hoveringTheBubbleOpensItsTabEvenOverAttention() {
        let state = IslandState()
        state.setNowPlaying(track(playing: true))
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        state.setHovering(true, opening: .media)
        #expect(state.phase == .expanded)
        #expect(state.selectedTab == .media)
    }

    // MARK: Files shelf

    private func file(_ path: String) -> ShelfItem {
        ShelfItem(url: URL(fileURLWithPath: path), isDirectory: false)
    }

    @Test func aShelfWithFilesMakesACollapsedIslandOpenOnFiles() {
        let state = IslandState()
        state.addShelfItems([file("/x/a.png")])
        state.setHovering(true)
        #expect(state.selectedTab == .files)
    }

    @Test func theFilesBubbleShowsOnlyCollapsedAtTheNotchWithFiles() {
        let state = IslandState()
        #expect(!state.filesBubbleShown)
        state.addShelfItems([file("/x/a.png")])
        #expect(state.filesBubbleShown)
        state.setHovering(true)
        #expect(!state.filesBubbleShown)
        state.setHovering(false)
        state.restoreAnchor(.edge(.bottom, fraction: 0.5))
        #expect(!state.filesBubbleShown)
        state.restoreAnchor(.notch)
        state.clearShelf()
        #expect(!state.filesBubbleShown)
    }

    @Test func aFileDragOverACollapsedIslandOpensItOnFiles() {
        let state = IslandState()
        state.setFileDragHovering(true)
        #expect(state.phase == .expanded)
        #expect(state.selectedTab == .files)
        #expect(state.isFileDragHovering)
        state.setFileDragHovering(false)
        #expect(!state.isFileDragHovering)
        #expect(state.phase == .expanded)
    }

    @Test func aFileDragOverAnOpenIslandSwitchesToFilesAndLeavesAgents() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setAgentSessions([agent("a", .idle)])
        state.setHovering(true)
        #expect(state.selectedTab == .agents)
        #expect(state.board.attention == .finished)
        state.setFileDragHovering(true)
        #expect(state.selectedTab == .files)
        #expect(state.board.attention == .none)
    }

    @Test func aFileDragWhileStretchingChangesNothing() {
        let state = IslandState()
        state.beginDrag(at: .zero, from: .zero)
        state.setFileDragHovering(true)
        #expect(state.phase == .stretching)
        #expect(!state.isFileDragHovering)
        #expect(state.selectedTab == TabOrder.default[0])
    }

    @Test func shelfChangesWorkInAnyPhase() {
        let state = IslandState()
        state.beginDrag(at: .zero, from: .zero)
        let a = file("/x/a.png")
        state.addShelfItems([a])
        #expect(state.shelf.items == [a])
        state.removeShelfItems([a.id])
        #expect(state.shelf.isEmpty)
    }

    @Test func beginningAConversionRecordsItOnce() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        let start = Date(timeIntervalSince1970: 100)
        state.beginConversion(a.id, label: "PDF", at: start)
        #expect(state.conversions[a.id]?.label == "PDF")
        #expect(state.conversions[a.id]?.revealStarted == nil)
        state.beginConversion(a.id, label: "JPEG", at: Date(timeIntervalSince1970: 200))
        #expect(state.conversions[a.id]?.label == "PDF")
        #expect(state.conversions[a.id]?.started == start)
        state.beginConversion(UUID(), label: "PDF", at: start)
        #expect(state.conversions.count == 1)
    }

    @Test func aConvertedRevealReplacesTheItemOnce() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        let out = URL(fileURLWithPath: "/x/a.pdf")
        let at = Date(timeIntervalSince1970: 5)
        state.revealConversion(a.id, result: .converted(url: out, isDirectory: false), at: at)
        #expect(state.shelf.items[0].url == out)
        #expect(state.shelf.items[0].id == a.id)
        #expect(state.conversions[a.id]?.revealStarted == at)
        state.revealConversion(
            a.id,
            result: .converted(url: URL(fileURLWithPath: "/x/other.pdf"), isDirectory: false),
            at: Date(timeIntervalSince1970: 9))
        #expect(state.shelf.items[0].url == out)
        #expect(state.conversions[a.id]?.revealStarted == at)
    }

    @Test func aFailedRevealKeepsTheFileAndRaisesANotice() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        state.revealConversion(
            a.id, result: .failed("Couldn't convert to PDF"), at: Date(timeIntervalSince1970: 2))
        #expect(state.shelf.items[0].url == a.url)
        #expect(state.shelfNotice == ShelfNotice(id: a.id, text: "Couldn't convert to PDF"))
        #expect(state.conversions[a.id]?.revealStarted != nil)
    }

    @Test func aCancelledRevealChangesNeitherFileNorNotice() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        state.revealConversion(a.id, result: .cancelled, at: Date(timeIntervalSince1970: 2))
        #expect(state.shelf.items[0].url == a.url)
        #expect(state.shelfNotice == nil)
        #expect(state.conversions[a.id]?.revealStarted != nil)
    }

    @Test func revealingWithoutAConversionIsIgnored() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.revealConversion(a.id, result: .failed("x"), at: Date(timeIntervalSince1970: 2))
        #expect(state.shelfNotice == nil)
        #expect(state.conversions.isEmpty)
    }

    @Test func removingAnItemDropsItsConversionAndNotice() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        state.revealConversion(a.id, result: .failed("x"), at: Date(timeIntervalSince1970: 2))
        state.removeShelfItems([a.id])
        #expect(state.conversions[a.id] == nil)
        #expect(state.shelfNotice == nil)
    }

    @Test func endingAConversionRemovesTheEntry() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        state.endConversion(a.id)
        #expect(state.conversions.isEmpty)
    }

    @Test func beginningAConversionClearsItsNoticeAndSelectingAnotherItemClearsOthers() {
        let state = IslandState()
        let (a, b) = (file("/x/a.png"), file("/x/b.png"))
        state.addShelfItems([a, b])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        state.revealConversion(a.id, result: .failed("x"), at: Date(timeIntervalSince1970: 2))
        state.endConversion(a.id)
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 3))
        #expect(state.shelfNotice == nil)
        state.revealConversion(a.id, result: .failed("y"), at: Date(timeIntervalSince1970: 4))
        state.selectShelfItems([a.id])
        #expect(state.shelfNotice != nil)
        state.selectShelfItems([b.id])
        #expect(state.shelfNotice == nil)
        #expect(state.shelf.selectedID == b.id)
    }

    @Test func restoringTheShelfSelectsTheFirst() {
        let state = IslandState()
        let (a, b) = (file("/x/a.png"), file("/x/b.png"))
        state.restoreShelf([a, b])
        #expect(state.shelf.items == [a, b])
        #expect(state.shelf.selectedID == a.id)
    }

    // MARK: Stacks, selection and hover on the shelf

    /// Whether anything observing `read` is told about `action`'s changes.
    private func notifies(_ read: @escaping () -> Void, whenDoing action: () -> Void) -> Bool {
        let fired = Flag()
        withObservationTracking(read) { fired.value = true }
        action()
        return fired.value
    }

    private final class Flag: @unchecked Sendable {
        var value = false
    }

    private func openFilesTab(_ state: IslandState) {
        state.setHovering(true, opening: .files)
    }

    @Test func droppingSeveralFormsOneStackAndOntoJoinsIt() {
        let state = IslandState()
        let (a, b, c) = (file("/x/a.png"), file("/x/b.png"), file("/x/c.png"))
        state.addShelfItems([a, b])
        #expect(state.shelf.stacks.count == 1)
        let stack = state.shelf.stacks[0].id
        state.addShelfItems([c], onto: stack)
        #expect(state.shelf.stacks.map { $0.items.map(\.id) } == [[c.id, a.id, b.id]])
        #expect(state.shelf.selection == [c.id])
    }

    @Test func movingSeparatingAndBringingToFrontGoThroughTheShelf() {
        let state = IslandState()
        let (a, b, c) = (file("/x/a.png"), file("/x/b.png"), file("/x/c.png"))
        state.addShelfItems([a])
        state.addShelfItems([b])
        state.addShelfItems([c])
        state.moveShelfItems([c.id, b.id], onto: a.id)
        #expect(state.shelf.stacks.map { $0.items.map(\.id) } == [[c.id, b.id, a.id]])
        state.bringShelfItemToFront(a.id)
        #expect(state.shelf.items.map(\.id) == [a.id, c.id, b.id])
        state.separateShelfItems([b.id])
        #expect(state.shelf.stacks.map { $0.items.map(\.id) } == [[a.id, c.id], [b.id]])
    }

    @Test func selectingAndTogglingGoThroughTheShelf() {
        let state = IslandState()
        let (a, b) = (file("/x/a.png"), file("/x/b.png"))
        state.addShelfItems([a, b])
        state.selectShelfItems([a.id])
        state.toggleShelfItems([b.id])
        #expect(state.shelf.selection == [a.id, b.id])
        state.toggleShelfItems([a.id])
        #expect(state.shelf.selection == [b.id])
    }

    @Test func removingSeveralDropsTheirConversionsAndNotice() {
        let state = IslandState()
        let (a, b, c) = (file("/x/a.png"), file("/x/b.png"), file("/x/c.png"))
        state.addShelfItems([a, b, c])
        for item in [a, b, c] {
            state.beginConversion(item.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        }
        state.revealConversion(a.id, result: .failed("x"), at: Date(timeIntervalSince1970: 2))
        state.removeShelfItems([a.id, b.id])
        #expect(Set(state.conversions.keys) == [c.id])
        #expect(state.shelfNotice == nil)
        #expect(state.shelf.items.map(\.id) == [c.id])
    }

    @Test func aNoticeSurvivesOnlyWhileItsFileIsSelected() {
        let state = IslandState()
        let (a, b) = (file("/x/a.png"), file("/x/b.png"))
        state.addShelfItems([a])
        state.addShelfItems([b])
        state.setShelfNotice(ShelfNotice(id: a.id, text: "x"))
        state.toggleShelfItems([a.id])
        #expect(state.shelfNotice != nil)
        state.selectShelfItems([b.id])
        #expect(state.shelfNotice == nil)
    }

    @Test func theShelfNoticeIsAssignedOnlyOnChange() {
        let state = IslandState()
        let notice = ShelfNotice(id: UUID(), text: "x")
        #expect(notifies({ _ = state.shelfNotice }, whenDoing: { state.setShelfNotice(nil) }) == false)
        #expect(notifies({ _ = state.shelfNotice }, whenDoing: { state.setShelfNotice(notice) }))
        #expect(notifies({ _ = state.shelfNotice }, whenDoing: { state.setShelfNotice(notice) }) == false)
        #expect(notifies({ _ = state.shelfNotice }, whenDoing: { state.setShelfNotice(nil) }))
    }

    @Test func aFailedRevealAssignsTheNoticeOnlyWhenItDiffers() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        state.setShelfNotice(ShelfNotice(id: a.id, text: "Couldn't convert to PDF"))
        let fired = notifies(
            { _ = state.shelfNotice },
            whenDoing: {
                state.revealConversion(
                    a.id, result: .failed("Couldn't convert to PDF"), at: Date(timeIntervalSince1970: 2))
            })
        #expect(!fired)
        #expect(state.conversions[a.id]?.revealStarted != nil)
    }

    @Test func selectingWhatIsSelectedAssignsNothing() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        #expect(!notifies({ _ = state.shelf }, whenDoing: { state.selectShelfItems([a.id]) }))
        #expect(!notifies({ _ = state.shelf }, whenDoing: { state.selectShelfItems([UUID()]) }))
        #expect(!notifies({ _ = state.shelf }, whenDoing: { state.removeShelfItems([UUID()]) }))
        #expect(!notifies({ _ = state.shelf }, whenDoing: { state.bringShelfItemToFront(a.id) }))
    }

    @Test func hoverAndDropTargetAssignOnlyOnChange() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        openFilesTab(state)
        let hover = ShelfHover(stack: a.id, hit: .body)
        #expect(!notifies({ _ = state.hoveredFile }, whenDoing: { state.setHoveredFile(nil) }))
        #expect(notifies({ _ = state.hoveredFile }, whenDoing: { state.setHoveredFile(hover) }))
        #expect(state.hoveredFile == hover)
        #expect(!notifies({ _ = state.hoveredFile }, whenDoing: { state.setHoveredFile(hover) }))
        #expect(notifies({ _ = state.hoveredFile }, whenDoing: {
            state.setHoveredFile(ShelfHover(stack: a.id, hit: .file(0)))
        }))
        #expect(!notifies({ _ = state.fileDropTarget }, whenDoing: { state.setFileDropTarget(nil) }))
        #expect(notifies({ _ = state.fileDropTarget }, whenDoing: { state.setFileDropTarget(a.id) }))
        #expect(!notifies({ _ = state.fileDropTarget }, whenDoing: { state.setFileDropTarget(a.id) }))
    }

    @Test func endingTheFileDragClearsTheDropTarget() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        state.setFileDragHovering(true)
        state.setFileDropTarget(a.id)
        state.setFileDragHovering(false)
        #expect(state.fileDropTarget == nil)
        #expect(!state.isFileDragHovering)
        #expect(!notifies({ _ = state.isFileDragHovering; _ = state.fileDropTarget }, whenDoing: {
            state.setFileDragHovering(false)
        }))
        #expect(notifies({ _ = state.isFileDragHovering }, whenDoing: { state.setFileDragHovering(true) }))
        #expect(!notifies({ _ = state.isFileDragHovering }, whenDoing: { state.setFileDragHovering(true) }))
    }

    @Test func filesOfOneDropArrivingApartFormOneStack() {
        let state = IslandState()
        state.addShelfItems([file("/x/a.png")])
        let drop = UUID()
        state.addShelfItems([file("/x/b.png")], into: drop)
        state.addShelfItems([file("/x/c.png")], into: drop)
        #expect(state.shelf.stacks.map { $0.items.map(\.name) } == [["b.png", "c.png"], ["a.png"]])
        #expect(state.shelf.stacks[0].id == drop)
        #expect(!notifies({ _ = state.shelf }, whenDoing: {
            state.addShelfItems([file("/x/c.png")], into: drop)
        }))
    }

    @Test func openingOnFilesOpensOrSwitchesButNeverDuringADrag() {
        let state = IslandState()
        state.openOnFiles()
        #expect(state.phase == .expanded)
        #expect(state.selectedTab == .files)
        #expect(!state.isFileDragHovering)
        state.selectTab(.media)
        state.openOnFiles()
        #expect(state.selectedTab == .files)
        let dragged = IslandState()
        dragged.beginDrag(at: .zero, from: .zero)
        dragged.openOnFiles()
        #expect(dragged.phase == .stretching)
        #expect(dragged.selectedTab == TabOrder.default[0])
    }

    @Test func theSetApartCueMakesNoRoomAndEndsWithTheDrag() {
        let state = IslandState()
        state.openOnFiles()
        #expect(notifies({ _ = state.fileDragSetsApart }, whenDoing: { state.setFileDragSetsApart(true) }))
        #expect(!notifies({ _ = state.fileDragSetsApart }, whenDoing: { state.setFileDragSetsApart(true) }))
        #expect(state.fileDragSetsApart)
        #expect(!state.isFileDragHovering)
        state.setFileDragSetsApart(false)
        #expect(!state.fileDragSetsApart)
        state.setFileDragSetsApart(true)
        state.setFileDragHovering(false)
        #expect(!state.fileDragSetsApart)
        #expect(!notifies({ _ = state.fileDragSetsApart }, whenDoing: { state.setFileDragHovering(false) }))
    }

    @Test func hoverIsClearedByLeavingTheFilesTabOrCollapsing() {
        let state = IslandState()
        let a = file("/x/a.png")
        state.addShelfItems([a])
        openFilesTab(state)
        state.setHoveredFile(ShelfHover(stack: a.id, hit: .body))
        state.selectTab(.media)
        #expect(state.hoveredFile == nil)
        state.selectTab(.files)
        state.setHoveredFile(ShelfHover(stack: a.id, hit: .body))
        state.setHovering(false)
        #expect(state.phase == .collapsed)
        #expect(state.hoveredFile == nil)
        openFilesTab(state)
        state.setHoveredFile(ShelfHover(stack: a.id, hit: .file(0)))
        state.beginDrag(at: .zero, from: .zero)
        #expect(state.hoveredFile == nil)
    }

    @Test func hoverAndDropTargetFollowTheirStackOffTheShelf() {
        let state = IslandState()
        let (a, b) = (file("/x/a.png"), file("/x/b.png"))
        state.addShelfItems([a])
        state.addShelfItems([b])
        openFilesTab(state)
        state.setHoveredFile(ShelfHover(stack: a.id, hit: .body))
        state.setFileDropTarget(a.id)
        state.removeShelfItems([b.id])
        #expect(state.hoveredFile != nil)
        #expect(state.fileDropTarget == a.id)
        state.removeShelfItems([a.id])
        #expect(state.hoveredFile == nil)
        #expect(state.fileDropTarget == nil)
    }

    @Test func aConversionResultThatReplacesAnotherItemDropsItsConversion() {
        let state = IslandState()
        let (a, b) = (file("/x/a.png"), file("/x/b.pdf"))
        state.addShelfItems([a])
        state.addShelfItems([b])
        state.beginConversion(a.id, label: "PDF", at: Date(timeIntervalSince1970: 1))
        state.beginConversion(b.id, label: "PNG", at: Date(timeIntervalSince1970: 1))
        state.revealConversion(
            a.id, result: .converted(url: b.url, isDirectory: false), at: Date(timeIntervalSince1970: 2))
        #expect(state.shelf.items.map(\.id) == [a.id])
        #expect(Set(state.conversions.keys) == [a.id])
    }

    // MARK: Track glow

    private func song(_ title: String, playing: Bool = true, cover: UInt8? = nil) -> NowPlayingInfo {
        NowPlayingInfo(
            title: title, artist: "A", artworkData: cover.map { Data([$0]) }, isPlaying: playing,
            sourceName: "Music", sourceBundleIdentifier: "com.apple.Music")
    }

    /// Plays the light of the track that waits, as the view does once its wait is over.
    private func playAwaitedGlow(_ state: IslandState) {
        guard let serial = state.awaitedTrackGlow?.serial else { return }
        state.trackGlowSettled(serial)
        state.trackGlowWaitElapsed(serial)
    }

    @Test func aNewTrackWaitsForItsCoverThenLightsTheIsland() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        let awaited = state.awaitedTrackGlow
        #expect(awaited != nil)
        #expect(state.trackGlow == nil)

        state.trackGlowSettled(awaited?.serial ?? 0)
        #expect(state.awaitedTrackGlow == nil)
        #expect(state.trackGlow?.surface == .island)
        #expect(state.trackGlow?.source == NowPlayingSource(song("One")))

        state.trackGlowEnded(state.trackGlow?.serial ?? 0)
        #expect(state.trackGlow == nil)
    }

    @Test func withoutACoverTheLightPlaysWhenTheWaitIsOver() {
        let state = IslandState()
        state.setNowPlaying(song("One"))
        let serial = state.awaitedTrackGlow?.serial ?? 0
        state.trackGlowSettled(serial)
        #expect(state.trackGlow == nil)
        state.trackGlowWaitElapsed(serial)
        #expect(state.trackGlow?.surface == .island)
    }

    @Test func theLightWaitsForTheNewCoverNotTheOldOne() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        state.trackGlowEnded(state.trackGlow?.serial ?? 0)

        // The title changes first; the old cover is still there.
        state.setNowPlaying(song("Two", cover: 1))
        state.trackGlowSettled(state.awaitedTrackGlow?.serial ?? 0)
        #expect(state.trackGlow == nil)
        state.setNowPlaying(song("Two", cover: 2))
        #expect(state.trackGlow?.surface == .island)
        #expect(state.awaitedTrackGlow == nil)
    }

    @Test func aCoverThatArrivesBeforeTheShortestWaitDoesNotPlayEarly() {
        let state = IslandState()
        state.setNowPlaying(song("One"))
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.trackGlow == nil)
        #expect(state.awaitedTrackGlow != nil)
    }

    @Test func skippingQuicklyLightsOnlyTheLastTrack() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        let first = state.awaitedTrackGlow?.serial ?? 0
        state.setNowPlaying(song("Two", cover: 2))
        let second = state.awaitedTrackGlow?.serial ?? 0
        #expect(second != first)
        // The first track's wait reports late: nothing plays for it.
        state.trackGlowSettled(first)
        state.trackGlowWaitElapsed(first)
        #expect(state.trackGlow == nil)
        state.trackGlowSettled(second)
        #expect(state.trackGlow?.serial == second)
    }

    @Test func pausingAndResumingLightsNothing() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        state.trackGlowEnded(state.trackGlow?.serial ?? 0)
        state.setNowPlaying(song("One", playing: false, cover: 1))
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.awaitedTrackGlow == nil)
        #expect(state.trackGlow == nil)
    }

    @Test func musicInTheBubbleLightsTheBubble() {
        let state = IslandState()
        state.setAgentSessions([agent("a", .working)])
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.bubbleTab == .media)
        playAwaitedGlow(state)
        #expect(state.trackGlow?.surface == .bubble)
    }

    @Test func anAgentLightOnTheIslandKeepsTheTrackLightAway() {
        let state = IslandState()
        state.setTabOrder([.media, .agents])
        state.setAgentSessions([agent("a", .needsInput(prompt: nil))])
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.face == .media)
        playAwaitedGlow(state)
        #expect(state.trackGlow == nil)
        #expect(state.awaitedTrackGlow == nil)
    }

    @Test func noLightWhileTheIslandIsOpenAndNoneLater() {
        let state = IslandState()
        state.setHovering(true)
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        #expect(state.trackGlow == nil)
        state.setHovering(false)
        #expect(state.trackGlow == nil)
        #expect(state.awaitedTrackGlow == nil)
    }

    @Test func noLightWhereTheMusicHasNoFace() {
        let state = IslandState()
        state.restoreAnchor(.edge(.bottom, fraction: 0.5))
        state.setAgentSessions([agent("a", .working)])
        state.setNowPlaying(song("One", cover: 1))
        #expect(state.face == .agents)
        playAwaitedGlow(state)
        #expect(state.trackGlow == nil)
    }

    @Test func aLightThatLosesItsSurfaceGoesOut() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        #expect(state.trackGlow != nil)
        state.setHovering(true)
        #expect(state.trackGlow == nil)

        // On the island, an agent starts to work: the music moves out to the bubble.
        state.setHovering(false)
        state.setNowPlaying(song("Two", cover: 2))
        playAwaitedGlow(state)
        #expect(state.trackGlow?.surface == .island)
        state.setAgentSessions([agent("a", .working)])
        #expect(state.trackGlow == nil)
    }

    @Test func theSecondSourceLightsWithItsOwnTrack() {
        let state = IslandState()
        state.setNowPlaying(
            NowPlayingInfo(
                title: "Stream", artist: "", isPlaying: true, sourceName: "Chrome",
                sourceBundleIdentifier: "com.google.Chrome"))
        playAwaitedGlow(state)
        state.trackGlowEnded(state.trackGlow?.serial ?? 0)
        state.setCompanionPlaying(song("One", cover: 1))
        #expect(state.mediaSlots.count == 2)
        playAwaitedGlow(state)
        #expect(state.trackGlow?.source == NowPlayingSource(song("One")))
    }

    @Test func anEndedLightOfAnotherSerialIsLeftAlone() {
        let state = IslandState()
        state.setNowPlaying(song("One", cover: 1))
        playAwaitedGlow(state)
        let serial = state.trackGlow?.serial ?? 0
        state.trackGlowEnded(serial - 1)
        #expect(state.trackGlow?.serial == serial)
    }

    @Test func theSystemSnapshotIsKept() {
        let state = IslandState()
        #expect(state.system == nil)
        #expect(state.networkHistory.samples.isEmpty)
        var history = NetworkHistory()
        history.append(NetworkSpeed(down: 2_000, up: 200))
        let snapshot = SystemSnapshot(
            cpu: 0.3, gpu: 0.2, memory: MemoryUse(used: 20, total: 48),
            temperatures: Temperatures(cpu: 44, gpu: 37), network: NetworkSpeed(down: 2_000, up: 200),
            isOnline: true)
        state.setSystem(snapshot, history: history)
        #expect(state.system == snapshot)
        #expect(state.networkHistory == history)
    }
}
