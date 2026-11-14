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
}
