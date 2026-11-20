import Foundation
import Testing

@testable import SymbiodockCore

@Suite struct ArtworkPaletteTests {
    private static let red = TintColor(red: 0.9, green: 0.1, blue: 0.1)
    private static let blue = TintColor(red: 0.1, green: 0.2, blue: 0.9)
    private static let gray = TintColor(red: 0.5, green: 0.5, blue: 0.5)

    /// A square image whose pixel at (column, row) is `color(x, y)`, both 0...1.
    private func image(side: Int = 16, _ color: (Double, Double) -> TintColor) -> [TintColor] {
        (0..<side * side).map { index in
            color(
                (Double(index % side) + 0.5) / Double(side),
                (Double(index / side) + 0.5) / Double(side))
        }
    }

    private func tint(side: Int = 16, _ color: (Double, Double) -> TintColor) -> ArtworkTint? {
        ArtworkPalette.tint(pixels: image(side: side, color), width: side)
    }

    @Test func aCoverOfOneColourGivesThatColour() throws {
        let tint = try #require(tint { _, _ in Self.red })
        #expect(tint.stops.count == 1)
        let stop = tint.stops[0]
        #expect(stop.red > 0.8)
        #expect(stop.green < 0.4 && stop.blue < 0.4)
    }

    @Test func aCoverWithoutColourGivesNone() {
        #expect(tint { _, _ in Self.gray } == nil)
        #expect(tint { _, _ in TintColor(red: 0, green: 0, blue: 0) } == nil)
        #expect(tint { _, _ in TintColor(red: 1, green: 1, blue: 1) } == nil)
        #expect(ArtworkPalette.tint(pixels: [], width: 0) == nil)
        // A width that does not fit the pixels is not an image.
        #expect(ArtworkPalette.tint(pixels: image { _, _ in Self.red }, width: 7) == nil)
    }

    @Test func twoColoursComeInTheOrderTheyStandInTheCover() throws {
        let redLeft = try #require(tint { x, _ in x < 0.5 ? Self.red : Self.blue })
        #expect(redLeft.stops.count == 2)
        #expect(redLeft.stops[0].red > redLeft.stops[0].blue)
        #expect(redLeft.stops[1].blue > redLeft.stops[1].red)

        let blueLeft = try #require(tint { x, _ in x < 0.5 ? Self.blue : Self.red })
        #expect(blueLeft.stops[0].blue > blueLeft.stops[0].red)
        #expect(blueLeft.stops[1].red > blueLeft.stops[1].blue)
    }

    @Test func aRedPinkPurpleCoverGivesThatRun() throws {
        // Hue runs backwards from red (360°) through pink (320°) to purple (275°).
        let tint = try #require(
            tint(side: 32) { x, _ in ArtworkPalette.color(hue: (360 - 85 * x) / 360, saturation: 0.8, value: 0.9) })
        try #require(tint.stops.count == 3)
        let hues = tint.stops.map { ArtworkPalette.hue(of: $0) * 360 }
        // Red sits at either end of the wheel.
        #expect(hues[0] > 325 || hues[0] < 15)
        #expect((295...340).contains(hues[1]))
        #expect((265...305).contains(hues[2]))
        #expect(hues[1] > hues[2])
        #expect(hues[0] < 15 || hues[0] > hues[1])
    }

    @Test func aRunDownTheCoverStillPassesThroughTheMiddleColour() throws {
        // Top to bottom there is no left and right to order by; the hues must still be
        // neighbours, never red, purple, pink.
        let tint = try #require(
            tint(side: 32) { _, y in ArtworkPalette.color(hue: (360 - 85 * y) / 360, saturation: 0.8, value: 0.9) })
        try #require(tint.stops.count == 3)
        let hues = tint.stops.map { ArtworkPalette.hue(of: $0) * 360 }
        let ends = [hues[0], hues[2]]
        #expect((295...340).contains(hues[1]))
        #expect(ends.contains { $0 > hues[1] || $0 < 15 })
        #expect(ends.contains { $0 < hues[1] && $0 > 200 })
    }

    @Test func aSmallVividPartOnAGreyCoverStillTints() throws {
        let tint = try #require(tint { x, y in x < 0.3 && y < 0.3 ? Self.blue : Self.gray })
        #expect(tint.stops.count == 1)
        #expect(tint.stops[0].blue > tint.stops[0].red)
    }

    @Test func aFewStrayPixelsDoNot() {
        // One pixel in 256.
        #expect(tint { x, y in x < 0.07 && y < 0.07 ? Self.blue : Self.gray } == nil)
    }

    @Test func darkColoursAreLiftedUntilTheyReadOnBlack() throws {
        let navy = try #require(tint { _, _ in TintColor(red: 0.02, green: 0.03, blue: 0.3) })
        let maroon = try #require(tint { _, _ in TintColor(red: 0.3, green: 0.03, blue: 0.05) })
        let pureBlue = try #require(tint { _, _ in TintColor(red: 0, green: 0, blue: 1) })
        for stop in [navy.stops[0], maroon.stops[0], pureBlue.stops[0]] {
            #expect(ArtworkPalette.luminance(of: stop) >= ArtworkPalette.minimumLuminance - 0.001)
        }
        // Lifted, not washed out: navy is still blue.
        #expect(navy.stops[0].blue > navy.stops[0].red + 0.3)
    }

    @Test func aMinorColourIsLeftOut() throws {
        // A tenth of the cover is not one of its colours.
        let tint = try #require(tint(side: 20) { x, _ in x < 0.1 ? Self.blue : Self.red })
        #expect(tint.stops.count == 1)
        #expect(tint.stops[0].red > tint.stops[0].blue)
    }

    @Test func theColourAlongTheRunIsBlendedBetweenItsStops() {
        let a = TintColor(red: 1, green: 0, blue: 0)
        let b = TintColor(red: 0, green: 0, blue: 1)
        let c = TintColor(red: 0, green: 1, blue: 0)
        let run = ArtworkTint(stops: [a, b, c])
        #expect(run.color(at: 0) == a)
        #expect(run.color(at: 0.5) == b)
        #expect(run.color(at: 1) == c)
        #expect(run.color(at: 0.25) == TintColor(red: 0.5, green: 0, blue: 0.5))
        #expect(run.color(at: -1) == a)
        #expect(run.color(at: 2) == c)
        #expect(ArtworkTint(stops: [a]).color(at: 0.7) == a)
    }
}
