import Foundation
import Testing
@testable import SymbiodockCore

struct PlaybackProgressTests {
    let measuredAt = Date(timeIntervalSince1970: 1_000)

    func info(elapsed: TimeInterval?, duration: TimeInterval?, playing: Bool, stamped: Bool = true)
        -> NowPlayingInfo
    {
        NowPlayingInfo(
            title: "T", artist: "A", duration: duration, elapsed: elapsed,
            elapsedAt: stamped ? measuredAt : nil, isPlaying: playing, sourceName: "Music")
    }

    @Test func playingTrackAdvancesWithTheClock() {
        let track = info(elapsed: 10, duration: 100, playing: true)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(15)) == 25)
        #expect(PlaybackProgress.fraction(for: track, at: measuredAt.addingTimeInterval(15)) == 0.25)
    }

    @Test func pausedTrackStaysWhereItIs() {
        let track = info(elapsed: 10, duration: 100, playing: false)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(15)) == 10)
    }

    @Test func elapsedIsClampedToTheTrack() {
        let track = info(elapsed: 90, duration: 100, playing: true)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(60)) == 100)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(-500)) == 0)
    }

    @Test func unstampedPositionIsUsedAsIs() {
        let track = info(elapsed: 10, duration: 100, playing: true, stamped: false)
        #expect(PlaybackProgress.elapsed(for: track, at: measuredAt.addingTimeInterval(15)) == 10)
    }

    @Test func missingPositionOrDurationGivesNoFraction() {
        #expect(PlaybackProgress.fraction(
            for: info(elapsed: nil, duration: 100, playing: true), at: measuredAt) == nil)
        #expect(PlaybackProgress.fraction(
            for: info(elapsed: 10, duration: nil, playing: true), at: measuredAt) == nil)
    }
}
