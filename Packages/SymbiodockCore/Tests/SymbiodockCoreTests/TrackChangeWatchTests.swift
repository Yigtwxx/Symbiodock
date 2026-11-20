import Foundation
import Testing
@testable import SymbiodockCore

struct TrackChangeWatchTests {
    private func slot(
        _ title: String, artist: String = "A", playing: Bool = true, cover: UInt8? = nil,
        bundle: String = "com.apple.Music", origin: NowPlayingOrigin = .system
    ) -> NowPlayingSlot {
        NowPlayingSlot(
            info: NowPlayingInfo(
                title: title, artist: artist, artworkData: cover.map { Data([$0]) },
                isPlaying: playing, sourceName: "App", sourceBundleIdentifier: bundle),
            origin: origin)
    }

    private var music: NowPlayingSource { NowPlayingSource(slot("x").info) }

    @Test func theFirstTrackHeardPlayingIsAChange() {
        var watch = TrackChangeWatch()
        #expect(watch.update([slot("One")]) == [TrackChange(source: music, staleArtwork: nil)])
        #expect(watch.update([slot("One")]).isEmpty)
    }

    @Test func anotherTitleOrArtistIsAChange() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([slot("Two")]).count == 1)
        #expect(watch.update([slot("Two", artist: "B")]).count == 1)
    }

    @Test func pausingAndResumingIsNotAChange() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([slot("One", playing: false)]).isEmpty)
        #expect(watch.update([slot("One")]).isEmpty)
    }

    @Test func aTrackSkippedWhilePausedChangesWhenItPlays() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([slot("Two", playing: false)]).isEmpty)
        #expect(watch.update([slot("Two")]).count == 1)
    }

    @Test func aSourceThatGoesAndReturnsWithItsTrackIsNotAChange() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        #expect(watch.update([]).isEmpty)
        #expect(watch.update([slot("One", origin: .companion)]).isEmpty)
    }

    @Test func eachSourceIsWatchedOnItsOwn() {
        var watch = TrackChangeWatch()
        let stream = slot("Stream", bundle: "com.google.Chrome")
        #expect(watch.update([slot("One"), stream]).count == 2)
        // The slots change places: nothing new plays.
        #expect(watch.update([stream, slot("One")]).isEmpty)
        #expect(watch.update([stream, slot("Two")]) == [TrackChange(source: music, staleArtwork: nil)])
    }

    @Test func theChangeNamesTheCoverThatWasThereBefore() {
        var watch = TrackChangeWatch()
        _ = watch.update([slot("One")])
        // The cover arrives after the title.
        _ = watch.update([slot("One", cover: 1)])
        #expect(watch.update([slot("Two", cover: 1)]) == [TrackChange(source: music, staleArtwork: Data([1]))])
        _ = watch.update([slot("Two", cover: 2)])
        #expect(watch.update([slot("Three", cover: 2)]) == [TrackChange(source: music, staleArtwork: Data([2]))])
    }

    @Test func aTrackWithoutATitleIsNotATrack() {
        var watch = TrackChangeWatch()
        #expect(watch.update([slot("")]).isEmpty)
    }
}
