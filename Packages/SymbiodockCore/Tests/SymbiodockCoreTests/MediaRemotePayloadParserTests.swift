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
            isPlaying: true, sourceName: "Music", sourceBundleIdentifier: "com.apple.Music"))
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
        // The browser the user knows, not its GPU helper; the site is not the parser's to tell.
        #expect(info.sourceBundleIdentifier == "com.apple.Safari")
        #expect(info.site == nil)
    }

    @Test func payloadWithoutAnIdentifierHasNoSourceApp() throws {
        let info = try #require(
            try MediaRemotePayloadParser.info(fromStreamLine: #"{"payload":{"title":"T"}}"#))
        #expect(info.sourceBundleIdentifier == nil)
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

    @Test func lineSeparatorInsideATitleParses() throws {
        let line = "{\"type\":\"data\",\"diff\":false,\"payload\":{\"title\":\"A\u{2028}B\",\"playing\":true}}"

        #expect(try MediaRemotePayloadParser.info(fromStreamLine: Data(line.utf8))?.title == "A\u{2028}B")
    }

    // Key set and value types as produced by the helper's `stream` command; text and artwork
    // replaced with placeholders. (Nothing was playing when captured, so this is built from
    // a real sample of the keys and types.)
    @Test func recordedHelperPayloadParses() throws {
        let line = """
        {"type":"data","diff":false,"payload":{"playbackRate":1,"album":"Fixture Album",\
        "elapsedTime":1615.400995445,"timestamp":"2026-11-14T13:33:56Z",\
        "bundleIdentifier":"com.apple.WebKit.GPU","processIdentifier":3214,\
        "parentApplicationBundleIdentifier":"com.apple.Safari","title":"Fixture Title",\
        "uniqueIdentifier":12056643,"duration":9223372036854.7754,"artist":"Fixture Artist",\
        "contentItemIdentifier":"12056643","playing":true,"artworkMimeType":"image/jpeg",\
        "artworkData":"AQID"}}
        """

        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))

        #expect(info.title == "Fixture Title")
        #expect(info.artist == "Fixture Artist")
        #expect(info.album == "Fixture Album")
        #expect(info.artworkData == Data([1, 2, 3]))
        #expect(info.duration == nil)  // live-stream sentinel
        #expect(info.elapsed == 1615.400995445)
        #expect(info.elapsedAt == Date(timeIntervalSince1970: 1_794_663_236))
        #expect(info.isPlaying)
        #expect(info.sourceName == "Safari")
    }

    @Test func playingAsNumberIsAccepted() throws {
        func playing(_ literal: String) throws -> Bool? {
            let line = #"{"payload":{"title":"T","playing":\#(literal)}}"#
            return try MediaRemotePayloadParser.info(fromStreamLine: line)?.isPlaying
        }
        #expect(try playing("1") == true)
        #expect(try playing("0") == false)
    }

    @Test func playingOfAnotherTypeIsTreatedAsAbsent() throws {
        let line = #"{"payload":{"title":"T","playing":"yes"}}"#
        #expect(try MediaRemotePayloadParser.info(fromStreamLine: line)?.isPlaying == false)
    }

    @Test func durationAsStringIsTreatedAsAbsent() throws {
        let line = #"{"payload":{"title":"T","duration":"320","elapsedTime":5}}"#
        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))
        #expect(info.duration == nil)
        #expect(info.elapsed == 5)
    }

    @Test func elapsedTimeAsStringIsTreatedAsAbsent() throws {
        let line = #"{"payload":{"title":"T","elapsedTime":"5","duration":10}}"#
        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))
        #expect(info.elapsed == nil)
        #expect(info.duration == 10)
    }

    @Test func textFieldsOfAnotherTypeAreTreatedAsAbsent() throws {
        let line = #"{"payload":{"title":"T","artist":7,"album":false,"timestamp":1,"artworkData":[1],"bundleIdentifier":"com.apple.Music"}}"#
        let info = try #require(try MediaRemotePayloadParser.info(fromStreamLine: line))
        #expect(info.artist == "")
        #expect(info.album == nil)
        #expect(info.elapsedAt == nil)
        #expect(info.artworkData == nil)
        #expect(info.sourceName == "Music")
    }

    @Test func titleOfAnotherTypeMeansNothingIsPlaying() throws {
        #expect(try MediaRemotePayloadParser.info(fromStreamLine: #"{"payload":{"title":5}}"#) == nil)
    }

    @Test func parentIdentifierOfAnotherTypeFallsBackToBundleIdentifier() throws {
        let line = #"{"payload":{"title":"T","parentApplicationBundleIdentifier":3,"bundleIdentifier":"com.apple.Music"}}"#
        #expect(try MediaRemotePayloadParser.info(fromStreamLine: line)?.sourceName == "Music")
    }

    @Test func lineWithoutAPayloadObjectThrows() {
        for line in [#"{"type":"data"}"#, #"{"payload":null}"#, #"{"payload":"x"}"#, #"[1]"#, #"{"payload":[]}"#] {
            #expect(throws: (any Error).self) {
                try MediaRemotePayloadParser.info(fromStreamLine: line)
            }
        }
    }
}
