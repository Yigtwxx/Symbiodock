import CoreGraphics
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
}
