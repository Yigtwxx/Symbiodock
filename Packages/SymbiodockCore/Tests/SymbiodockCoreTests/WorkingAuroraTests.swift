import CoreGraphics
import Foundation
import Testing
@testable import SymbiodockCore

struct WorkingAuroraTests {
    private func edge(_ anchor: IslandAnchor) -> ScreenEdge {
        WorkingAurora.edge(
            dockedEdges: IslandLayout.dockedEdges(anchor: anchor),
            isVertical: IslandLayout.isSideDocked(anchor))
    }

    @Test func theLightPlaysAlongTheFreeLongEdge() {
        #expect(edge(.notch) == .bottom)
        #expect(edge(.edge(.top, fraction: 0.3)) == .bottom)
        #expect(edge(.edge(.bottom, fraction: 0.3)) == .top)
        #expect(edge(.edge(.left, fraction: 0.5)) == .right)
        #expect(edge(.edge(.right, fraction: 0.5)) == .left)
        #expect(edge(.corner(.topLeft)) == .bottom)
        #expect(edge(.corner(.topRight)) == .bottom)
        #expect(edge(.corner(.bottomLeft)) == .top)
        #expect(edge(.corner(.bottomRight)) == .top)
    }

    @Test func theBandLiesJustOutsideTheEdge() {
        let island = CGRect(x: 100, y: 0, width: 272, height: 34)
        let depth = WorkingAurora.depth
        #expect(abs(depth - 11.7) < 0.0001)
        #expect(WorkingAurora.band(island: island, edge: .bottom) == CGRect(x: 100, y: 34, width: 272, height: depth))
        #expect(WorkingAurora.band(island: island, edge: .top) == CGRect(x: 100, y: -depth, width: 272, height: depth))
        #expect(WorkingAurora.band(island: island, edge: .left) == CGRect(x: 100 - depth, y: 0, width: depth, height: 34))
        #expect(WorkingAurora.band(island: island, edge: .right) == CGRect(x: 372, y: 0, width: depth, height: 34))
    }

    @Test func theGlowBreathesBetweenItsBounds() {
        #expect(WorkingAurora.breath(at: 0) == 0)
        #expect(abs(WorkingAurora.breath(at: WorkingAurora.breathPeriod / 2) - 1) < 1e-9)
        #expect(abs(WorkingAurora.breath(at: WorkingAurora.breathPeriod)) < 1e-9)
        #expect(abs(WorkingAurora.glowOpacity(at: 0) - 0.6) < 1e-9)
        #expect(abs(WorkingAurora.glowOpacity(at: 1.2) - 1) < 1e-9)
        #expect(abs(WorkingAurora.stretch(at: 0) - 0.75) < 1e-9)
        #expect(abs(WorkingAurora.stretch(at: 1.2) - 1.3) < 1e-9)
        for step in 0...240 {
            let time = Double(step) / 50
            #expect((0.6...1).contains(WorkingAurora.glowOpacity(at: time)))
            #expect((0.75...1.3).contains(WorkingAurora.stretch(at: time)))
        }
    }

    @Test func theColoursTravelOneRunInAPeriod() {
        #expect(WorkingAurora.flow(at: 0) == 0)
        #expect(abs(WorkingAurora.flow(at: 1.6) - 0.5) < 1e-9)
        #expect(abs(WorkingAurora.flow(at: 3.2 + 0.8) - 0.25) < 1e-9)
        #expect(abs(WorkingAurora.flow(at: -0.8) - 0.75) < 1e-9)
    }

    @Test func theGlowAndTheLineLieInsideTheEdge() {
        let glow = WorkingAurora.glowRect(length: 272, stretch: 1)
        #expect(abs(glow.minX - 8) < 1e-9)
        #expect(abs(glow.minY) < 1e-9)
        #expect(abs(glow.width - 256) < 1e-9)
        #expect(abs(glow.height - 9) < 1e-9)
        #expect(abs(WorkingAurora.glowRect(length: 272, stretch: 1.3).height - 11.7) < 1e-9)
        let line = WorkingAurora.lineRect(length: 272)
        #expect(abs(line.minX - 9) < 1e-9)
        #expect(abs(line.minY) < 1e-9)
        #expect(abs(line.width - 254) < 1e-9)
        #expect(abs(line.height - 1) < 1e-9)
    }

    @Test func aShortEdgeLeavesNoNegativeWidth() {
        #expect(WorkingAurora.glowRect(length: 10, stretch: 1).width == 0)
        #expect(WorkingAurora.lineRect(length: 10).width == 0)
    }

    @Test func theEndsFadeOverAFixedLengthOrHalfAShortPiece() {
        func matches(_ got: [Double], _ want: [Double]) -> Bool {
            got.count == want.count && zip(got, want).allSatisfy { abs($0 - $1) < 1e-9 }
        }
        #expect(matches(WorkingAurora.endLocations(length: 280), [0, 0.05, 0.95, 1]))
        #expect(matches(WorkingAurora.endLocations(length: 20), [0, 0.5, 0.5, 1]))
        #expect(matches(WorkingAurora.endLocations(length: 0), [0, 0.5, 0.5, 1]))
    }

    @Test func theGlowFallsOffFromTheEdgeToNothing() {
        let falloff = WorkingAurora.falloff
        #expect(falloff.first?.place == 0)
        #expect(falloff.first?.strength == 1)
        #expect(falloff.last?.place == 1)
        #expect(falloff.last?.strength == 0)
        for (before, after) in zip(falloff, falloff.dropFirst()) {
            #expect(after.place > before.place)
            #expect(after.strength < before.strength)
        }
    }

    @Test func theMeasuresMatchTheSpec() {
        #expect(WorkingAurora.flowPeriod == 3.2)
        #expect(WorkingAurora.breathPeriod == 2.4)
        #expect(WorkingAurora.reach == 9)
        #expect(WorkingAurora.lineWidth == 1)
        #expect(WorkingAurora.lineInset == 9)
        #expect(WorkingAurora.glowInset == 8)
        #expect(WorkingAurora.stillGlow == 0.8)
        #expect(WorkingAurora.fade == 0.35)
    }

    @Test func theLightTurnsMintInStepWithTheSeal() {
        #expect(WorkingAurora.finishTintDelay == 0.75)
        #expect(abs(WorkingAurora.finishTintDuration - 0.2) < 1e-9)
        #expect(WorkingAurora.tintBack == 0.3)
        #expect(WorkingAurora.finishTint(at: 0) == 0)
        #expect(WorkingAurora.finishTint(at: 0.75) == 0)
        #expect(abs(WorkingAurora.finishTint(at: 0.95) - 1) < 1e-9)
        #expect(WorkingAurora.finishTint(at: 1.7) == 1)
        var last = 0.0
        for step in 0...170 {
            let tint = WorkingAurora.finishTint(at: Double(step) / 100)
            #expect(tint >= last - 1e-12)
            last = tint
        }
    }
}
