import Foundation
import Testing
@testable import SymbiodockCore

struct AppleMusicPayloadParserTests {
    let now = Date(timeIntervalSince1970: 5_000)

    @Test func playingTrackBecomesInfo() {
        let output = "One More Time\nDaft Punk\nDiscovery\n320.5\n42.25\nplaying"

        #expect(AppleMusicPayloadParser.info(fromScriptOutput: output, at: now) == NowPlayingInfo(
            title: "One More Time", artist: "Daft Punk", album: "Discovery",
            duration: 320.5, elapsed: 42.25, elapsedAt: now,
            isPlaying: true, sourceName: "Music"))
    }

    @Test func pausedTrackIsNotPlaying() {
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "T\nA\n\n100\n5\npaused", at: now)

        #expect(info?.isPlaying == false)
        #expect(info?.album == nil)
    }

    @Test func decimalCommaIsAccepted() {
        // AppleScript formats numbers with the user's locale.
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "T\nA\nB\n320,5\n42,25\nplaying", at: now)

        #expect(info?.duration == 320.5)
        #expect(info?.elapsed == 42.25)
    }

    @Test func stoppedOrMalformedOutputMeansNothingIsPlaying() {
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "stopped", at: now) == nil)
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "", at: now) == nil)
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "\nA\nB\n1\n1\nplaying", at: now) == nil)
    }
}
