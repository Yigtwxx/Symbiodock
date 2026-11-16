import Foundation
import Testing
@testable import SymbiodockCore

struct NowPlayingClientsParserTests {
    // Key set and value types as printed by the helper's `get-clients` on macOS 27.0.1 while
    // Safari and Music played at the same time; text and artwork replaced with placeholders.
    private let recordedLine = """
        [{"playbackRate":1,"album":"","elected":true,"elapsedTime":2274.722872657,\
        "timestamp":"2026-11-16T12:27:54Z","processIdentifier":74124,\
        "parentApplicationBundleIdentifier":"com.apple.Safari",\
        "bundleIdentifier":"com.apple.WebKit.GPU","title":"Fixture Stream",\
        "uniqueIdentifier":4019461,"duration":7822.621,"artist":"Fixture Channel",\
        "contentItemIdentifier":"4019461","playing":true},\
        {"composer":"Fixture Composer","title":"Fixture Song","duration":184.663,\
        "bundleIdentifier":"com.apple.Music","uniqueIdentifier":-794709725350339894,\
        "contentItemIdentifier":"8967::8977","isMusicApp":true,"elapsedTime":1.929207885,\
        "queueIndex":1,"elected":false,"artworkMimeType":"image/jpeg",\
        "mediaType":"MRMediaRemoteMediaTypeMusic","playing":true,\
        "timestamp":"2026-11-16T12:26:58Z","artist":"Fixture Artist","trackNumber":6,\
        "processIdentifier":69373,"totalQueueCount":24,"totalTrackCount":11,\
        "album":"Fixture Album","playbackRate":1,"genre":"Pop","artworkData":"AQID"}]
        """

    @Test func recordedLineGivesEveryClientInOrder() throws {
        let clients = NowPlayingClientsParser.clients(fromStreamLine: recordedLine)

        try #require(clients.count == 2)
        #expect(clients.map(\.pid) == [74124, 69373])
        #expect(clients.map(\.isElected) == [true, false])
        #expect(clients[0].info == NowPlayingInfo(
            title: "Fixture Stream", artist: "Fixture Channel", duration: 7822.621,
            elapsed: 2274.722872657, elapsedAt: Date(timeIntervalSince1970: 1_794_832_074),
            isPlaying: true, sourceName: "Safari", sourceBundleIdentifier: "com.apple.Safari"))
        #expect(clients[1].info.title == "Fixture Song")
        #expect(clients[1].info.album == "Fixture Album")
        #expect(clients[1].info.artworkData == Data([1, 2, 3]))
        #expect(clients[1].info.sourceName == "Music")
        #expect(clients[1].info.sourceBundleIdentifier == "com.apple.Music")
    }

    @Test func emptyArrayMeansNoClients() {
        #expect(NowPlayingClientsParser.clients(fromStreamLine: "[]").isEmpty)
    }

    @Test func badLinesMeanNoClients() {
        for line in ["not json", "", "null", #"{"payload":{"title":"T"}}"#, "[1,"] {
            #expect(NowPlayingClientsParser.clients(fromStreamLine: line).isEmpty)
        }
    }

    @Test func entriesThatCannotBeUsedAreSkipped() throws {
        let line = """
            [{"title":"No pid","playing":true},\
            {"title":"Zero pid","processIdentifier":0,"playing":true},\
            {"title":"","processIdentifier":5,"playing":true},\
            {"processIdentifier":6,"playing":true},\
            7,"text",null,\
            {"title":"Pid as text","processIdentifier":"8"},\
            {"title":"Kept","processIdentifier":9,"playing":false,"bundleIdentifier":"com.spotify.client"}]
            """

        let clients = NowPlayingClientsParser.clients(fromStreamLine: line)

        #expect(clients.map(\.pid) == [9])
        let kept = try #require(clients.first)
        #expect(kept.info.sourceName == "Spotify")
        #expect(!kept.info.isPlaying)
    }

    @Test func missingOrOddElectedFlagMeansNotElected() {
        let line = """
            [{"title":"A","processIdentifier":1},{"title":"B","processIdentifier":2,"elected":"yes"}]
            """
        #expect(NowPlayingClientsParser.clients(fromStreamLine: line).map(\.isElected) == [false, false])
    }

    @Test func lineSeparatorInsideATitleParses() {
        let line = "[{\"title\":\"A\u{2028}B\",\"processIdentifier\":3,\"playing\":true}]"

        #expect(NowPlayingClientsParser.clients(fromStreamLine: Data(line.utf8)).first?.info.title
            == "A\u{2028}B")
    }
}
