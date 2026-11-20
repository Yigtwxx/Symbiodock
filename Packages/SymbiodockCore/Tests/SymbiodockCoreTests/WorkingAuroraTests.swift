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
}
