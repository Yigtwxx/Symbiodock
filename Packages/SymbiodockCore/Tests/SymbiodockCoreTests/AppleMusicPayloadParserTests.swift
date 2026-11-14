import Foundation
import Testing
@testable import SymbiodockCore

struct AppleMusicPayloadParserTests {
    let now = Date(timeIntervalSince1970: 5_000)

    @Test func playingTrackBecomesInfo() {
        let output = "One More Time\u{1F}Daft Punk\u{1F}Discovery\u{1F}320.5\u{1F}42.25\u{1F}playing"

        #expect(AppleMusicPayloadParser.info(fromScriptOutput: output, at: now) == NowPlayingInfo(
            title: "One More Time", artist: "Daft Punk", album: "Discovery",
            duration: 320.5, elapsed: 42.25, elapsedAt: now,
            isPlaying: true, sourceName: "Music"))
    }

    @Test func pausedTrackIsNotPlaying() {
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "T\u{1F}A\u{1F}\u{1F}100\u{1F}5\u{1F}paused", at: now)

        #expect(info?.isPlaying == false)
        #expect(info?.album == nil)
    }

    @Test func decimalCommaIsAccepted() {
        // AppleScript formats numbers with the user's locale.
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "T\u{1F}A\u{1F}B\u{1F}320,5\u{1F}42,25\u{1F}playing", at: now)

        #expect(info?.duration == 320.5)
        #expect(info?.elapsed == 42.25)
    }

    @Test func stoppedOrMalformedOutputMeansNothingIsPlaying() {
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "stopped", at: now) == nil)
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "", at: now) == nil)
        #expect(AppleMusicPayloadParser.info(fromScriptOutput: "\u{1F}A\u{1F}B\u{1F}1\u{1F}1\u{1F}playing", at: now) == nil)
    }

    @Test func titleWithANewlineSurvives() {
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "Line one\nLine two\u{1F}A\u{1F}B\u{1F}100\u{1F}5\u{1F}playing", at: now)

        #expect(info?.title == "Line one\nLine two")
    }

    @Test func streamWithoutDurationStillYieldsTheTrack() {
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "Radio\u{1F}\u{1F}\u{1F}\u{1F}0\u{1F}playing", at: now)

        #expect(info?.title == "Radio")
        #expect(info?.duration == nil)
    }

    @Test func scientificNotationIsParsed() {
        let info = AppleMusicPayloadParser.info(
            fromScriptOutput: "T\u{1F}A\u{1F}B\u{1F}1.002E+4\u{1F}5\u{1F}playing", at: now)

        #expect(info?.duration == 10020)
    }
}
