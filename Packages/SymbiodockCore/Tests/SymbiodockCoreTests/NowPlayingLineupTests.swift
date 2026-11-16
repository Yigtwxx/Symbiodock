import Testing
@testable import SymbiodockCore

@MainActor
struct NowPlayingLineupTests {
    private func info(
        _ title: String, playing: Bool = true, bundle: String?, name: String = "App"
    ) -> NowPlayingInfo {
        NowPlayingInfo(
            title: title, artist: "", isPlaying: playing, sourceName: name,
            sourceBundleIdentifier: bundle)
    }

    private var stream: NowPlayingInfo { info("Stream", bundle: "com.google.Chrome") }
    private var song: NowPlayingInfo { info("Song", bundle: "com.apple.Music", name: "Music") }

    @Test func nothingPlayingMeansNoSlots() {
        #expect(NowPlayingLineup.slots(system: nil, companion: nil).isEmpty)
    }

    @Test func oneSourceGivesOneSlot() {
        #expect(NowPlayingLineup.slots(system: stream, companion: nil)
            == [NowPlayingSlot(info: stream, origin: .system)])
        #expect(NowPlayingLineup.slots(system: nil, companion: song)
            == [NowPlayingSlot(info: song, origin: .companion)])
    }

    @Test func twoSourcesPutTheSystemOneInFront() {
        let slots = NowPlayingLineup.slots(system: stream, companion: song)
        #expect(slots.map(\.origin) == [.system, .companion])
    }

    @Test func theSameAppIsOneSource() {
        let fromSystem = info("Song", bundle: "com.apple.Music", name: "Music")
        #expect(NowPlayingLineup.slots(system: fromSystem, companion: song).map(\.origin) == [.system])
    }

    @Test func sourcesWithoutIdentifiersAreComparedByName() {
        let unnamed = info("Song", bundle: nil, name: "Music")
        #expect(NowPlayingLineup.slots(system: unnamed, companion: song).count == 1)
        #expect(NowPlayingLineup.slots(system: info("X", bundle: nil), companion: song).count == 2)
    }

    @Test func aPlayingSourceGoesInFrontOfAPausedOne() {
        var paused = stream
        paused.isPlaying = false
        #expect(NowPlayingLineup.slots(system: paused, companion: song).map(\.origin)
            == [.companion, .system])
        var pausedSong = song
        pausedSong.isPlaying = false
        #expect(NowPlayingLineup.slots(system: paused, companion: pausedSong).map(\.origin)
            == [.system, .companion])
    }

    // MARK: - In the island's state

    @Test func stateShowsBothSourcesAndSpeaksForTheFirst() {
        let state = IslandState()
        state.setNowPlaying(stream)
        state.setCompanionPlaying(song)

        #expect(state.mediaSlots.map(\.info.title) == ["Stream", "Song"])
        #expect(state.nowPlaying == stream)
        #expect(state.mediaWings)
    }

    @Test func pausedSecondSourceRetiresAfterTheGraceAndReturnsWhenItPlays() {
        let state = IslandState()
        var pausedSong = song
        pausedSong.isPlaying = false
        state.setNowPlaying(stream)
        state.setCompanionPlaying(pausedSong)
        #expect(state.mediaSlots.count == 2)

        state.pausedGraceElapsed()
        #expect(state.mediaSlots.map(\.origin) == [.system])
        #expect(state.mediaWings)

        // Another update of the paused player does not bring it back.
        state.setCompanionPlaying(pausedSong)
        #expect(state.mediaSlots.count == 1)

        state.setCompanionPlaying(song)
        #expect(state.mediaSlots.count == 2)
    }

    @Test func aRetiredSourceIsShownAgainWhenItIsTheOnlyOne() {
        let state = IslandState()
        var pausedSong = song
        pausedSong.isPlaying = false
        state.setNowPlaying(stream)
        state.setCompanionPlaying(pausedSong)
        state.pausedGraceElapsed()

        state.setNowPlaying(nil)

        #expect(state.nowPlaying == pausedSong)
    }

    @Test func wingsFollowTheFrontSource() {
        let state = IslandState()
        var paused = stream
        paused.isPlaying = false
        state.setNowPlaying(paused)
        #expect(!state.mediaWings)

        state.setCompanionPlaying(song)
        #expect(state.mediaWings)
        #expect(state.nowPlaying == song)

        state.setCompanionPlaying(nil)
        state.pausedGraceElapsed()
        #expect(!state.mediaWings)

        state.setNowPlaying(nil)
        #expect(state.mediaSlots.isEmpty)
    }
}
