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

    // MARK: - Other apps the system knows about

    private var safari: NowPlayingInfo { info("Kick", bundle: "com.apple.Safari", name: "Safari") }
    private var spotify: NowPlayingInfo { info("Tune", bundle: "com.spotify.client", name: "Spotify") }

    private func client(
        _ info: NowPlayingInfo, pid: Int32, elected: Bool = false
    ) -> NowPlayingClient {
        NowPlayingClient(pid: pid, isElected: elected, info: info)
    }

    @Test func aBrowserIsShownWhileMusicIsTheElectedOne() {
        // The reported bug: Music is elected, so system and companion are both Music and the
        // browser was lost.
        let slots = NowPlayingLineup.slots(
            system: song, companion: song,
            others: [client(song, pid: 2, elected: true), client(safari, pid: 1)])

        #expect(slots == [
            NowPlayingSlot(info: song, origin: .system),
            NowPlayingSlot(info: safari, origin: .client(pid: 1)),
        ])
    }

    @Test func theCompanionKeepsItsPlaceWhenTheBrowserIsTheElectedOne() {
        let slots = NowPlayingLineup.slots(
            system: safari, companion: song,
            others: [client(safari, pid: 1, elected: true), client(song, pid: 2)])

        #expect(slots == [
            NowPlayingSlot(info: safari, origin: .system),
            NowPlayingSlot(info: song, origin: .companion),
        ])
    }

    @Test func pausedOrElectedAppsAreNotAdded() {
        var pausedSafari = safari
        pausedSafari.isPlaying = false

        #expect(NowPlayingLineup.slots(
            system: song, companion: nil, others: [client(pausedSafari, pid: 1)]
        ).map(\.origin) == [.system])
        #expect(NowPlayingLineup.slots(
            system: song, companion: nil, others: [client(safari, pid: 1, elected: true)]
        ).map(\.origin) == [.system])
    }

    @Test func anAppAlreadyShownIsNotAddedAgain() {
        let slots = NowPlayingLineup.slots(
            system: safari, companion: nil, others: [client(safari, pid: 7)])

        #expect(slots.map(\.origin) == [.system])
    }

    @Test func threePlayingAppsStillGiveTwoSlots() {
        let withCompanion = NowPlayingLineup.slots(
            system: safari, companion: song, others: [client(spotify, pid: 3)])
        #expect(withCompanion.map(\.origin) == [.system, .companion])

        // First come, first kept: the helper's order decides.
        let withoutCompanion = NowPlayingLineup.slots(
            system: song, companion: song,
            others: [client(spotify, pid: 3), client(safari, pid: 1)])
        #expect(withoutCompanion.map(\.origin) == [.system, .client(pid: 3)])
    }

    @Test func anotherAppCanFillASlotWithoutTheSystemSource() {
        #expect(NowPlayingLineup.slots(
            system: nil, companion: nil, others: [client(safari, pid: 1)])
            == [NowPlayingSlot(info: safari, origin: .client(pid: 1))])
        #expect(NowPlayingLineup.slots(
            system: nil, companion: song, others: [client(safari, pid: 1)]
        ).map(\.origin) == [.companion, .client(pid: 1)])
    }

    @Test func aPlayingAppGoesInFrontOfAPausedSystemSource() {
        var pausedSong = song
        pausedSong.isPlaying = false

        let slots = NowPlayingLineup.slots(
            system: pausedSong, companion: nil, others: [client(safari, pid: 1)])

        #expect(slots.map(\.origin) == [.client(pid: 1), .system])
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

    @Test func stateShowsAnotherPlayingAppNextToTheElectedOne() {
        let state = IslandState()
        state.setNowPlaying(song)
        state.setCompanionPlaying(song)
        #expect(state.mediaSlots.map(\.origin) == [.system])

        state.setOtherPlaying([client(song, pid: 2, elected: true), client(safari, pid: 1)])
        #expect(state.mediaSlots.map(\.origin) == [.system, .client(pid: 1)])
        #expect(state.nowPlaying == song)

        state.setOtherPlaying([])
        #expect(state.mediaSlots.map(\.origin) == [.system])
    }

    @Test func aPausedSystemSourceBehindAnotherAppRetiresAfterTheGrace() {
        let state = IslandState()
        var pausedSong = song
        pausedSong.isPlaying = false
        state.setNowPlaying(pausedSong)
        state.setOtherPlaying([client(safari, pid: 1)])
        #expect(state.mediaSlots.map(\.origin) == [.client(pid: 1), .system])

        state.pausedGraceElapsed()
        #expect(state.mediaSlots.map(\.origin) == [.client(pid: 1)])
        #expect(state.mediaWings)

        state.setNowPlaying(song)
        #expect(state.mediaSlots.map(\.origin) == [.system, .client(pid: 1)])
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
