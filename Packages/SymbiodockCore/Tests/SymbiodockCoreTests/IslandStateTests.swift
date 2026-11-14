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
        #expect(state.tabOrder == [.media, .agents])
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
        #expect(state.tabOrder == [.media, .agents])
    }
}
