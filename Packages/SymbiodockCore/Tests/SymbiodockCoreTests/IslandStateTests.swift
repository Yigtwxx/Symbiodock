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
}
