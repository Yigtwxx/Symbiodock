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

    @Test func mirrorsTheCurrentTrack() {
        let state = IslandState()
        #expect(!state.hasTrack)

        let track = NowPlayingInfo(title: "T", artist: "A", isPlaying: true, sourceName: "Music")
        state.setNowPlaying(track)
        #expect(state.nowPlaying == track)
        #expect(state.hasTrack)

        state.setNowPlaying(nil)
        #expect(!state.hasTrack)
    }
}
