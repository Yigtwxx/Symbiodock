import Foundation
import Testing
@testable import SymbiodockCore

struct MediaRemotePayloadParserTests {
    @Test func fullPayloadBecomesInfo() throws {
        let line = """
        {"type":"data","diff":false,"payload":{"playbackRate":1,"album":"Discovery",\
        "elapsedTime":42.5,"timestamp":"2026-11-14T13:33:56Z","bundleIdentifier":"com.apple.Music",\
        "title":"One More Time","duration":320.0,"artist":"Daft Punk","playing":true}}
        """

        let info = try MediaRemotePayloadParser.info(fromStreamLine: line)

        #expect(info == NowPlayingInfo(
            title: "One More Time", artist: "Daft Punk", album: "Discovery",
            duration: 320, elapsed: 42.5,
            elapsedAt: Date(timeIntervalSince1970: 1_794_663_236),
            isPlaying: true, sourceName: "Music"))
    }

    @Test func emptyPayloadMeansNothingIsPlaying() throws {
        #expect(try MediaRemotePayloadParser.info(
            fromStreamLine: #"{"type":"data","diff":false,"payload":{}}"#) == nil)
    }

    @Test func payloadWithoutATitleMeansNothingIsPlaying() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":true,"title":""}}"#
        #expect(try MediaRemotePayloadParser.info(fromStreamLine: line) == nil)
    }

    @Test func liveStreamDurationAndEmptyStringsAreDropped() throws {
        let line = """
        {"type":"data","diff":false,"payload":{"album":"","elapsedTime":1615.4,\
        "bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari",\
        "title":"Live Stream","duration":9223372036854.7754,"artist":"","playing":true}}
        """

        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))

        #expect(info.duration == nil)
        #expect(info.album == nil)
        #expect(info.artist == "")
        #expect(info.elapsedAt == nil)
        #expect(info.sourceName == "Safari")
    }

    @Test func artworkIsDecodedFromBase64() throws {
        let line = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Music","playing":false,"title":"T","artworkData":"AQID"}}"#

        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))

        #expect(info.artworkData == Data([1, 2, 3]))
        #expect(!info.isPlaying)
    }

    @Test func malformedLineThrows() {
        #expect(throws: (any Error).self) {
            try MediaRemotePayloadParser.info(fromStreamLine: "not json")
        }
    }
}
