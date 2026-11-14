import Foundation
import Testing
@testable import SymbiodockCore

struct IslandAnchorTests {
    @Test func anchorsSurviveARoundTrip() {
        let anchors: [IslandAnchor] = [.notch, .edge(.left, fraction: 0.25), .corner(.bottomRight)]
        for anchor in anchors {
            #expect(AnchorCodec.decode(AnchorCodec.encode(anchor)) == anchor)
        }
    }

    @Test func undecodableDataFallsBackToTheNotch() {
        #expect(AnchorCodec.decode(nil) == .notch)
        #expect(AnchorCodec.decode(Data()) == .notch)
        #expect(AnchorCodec.decode(Data("junk".utf8)) == .notch)
    }

    @Test func edgeFractionIsClampedWhenDecoding() {
        let high = AnchorCodec.encode(.edge(.top, fraction: 1.7))
        let low = AnchorCodec.encode(.edge(.top, fraction: -3))

        #expect(AnchorCodec.decode(high) == .edge(.top, fraction: 1))
        #expect(AnchorCodec.decode(low) == .edge(.top, fraction: 0))
    }

    @Test func nonFiniteFractionIsEncodedAsTheMiddle() {
        for value in [Double.nan, .infinity, -.infinity] {
            let data = AnchorCodec.encode(.edge(.left, fraction: value))
            #expect(!data.isEmpty)
            #expect(AnchorCodec.decode(data) == .edge(.left, fraction: 0.5))
        }
    }

    @Test func savedPositionsFromEarlierBuildsStillDecode() {
        // The exact JSON a build wrote; a rename must not silently reset saved positions.
        let left = Data(#"{"edge":{"_0":"left","fraction":0.25}}"#.utf8)
        let corner = Data(#"{"corner":{"_0":"bottomRight"}}"#.utf8)
        let notch = Data(#"{"notch":{}}"#.utf8)

        #expect(AnchorCodec.decode(left) == .edge(.left, fraction: 0.25))
        #expect(AnchorCodec.decode(corner) == .corner(.bottomRight))
        #expect(AnchorCodec.decode(notch) == .notch)
        #expect(String(decoding: AnchorCodec.encode(.edge(.left, fraction: 0.25)), as: UTF8.self) == String(decoding: left, as: UTF8.self))
        #expect(AnchorCodec.encode(.corner(.bottomRight)) == corner)
        #expect(AnchorCodec.encode(.notch) == notch)
    }
}
