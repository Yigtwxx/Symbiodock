import CoreGraphics
import Testing
@testable import SymbiodockCore

struct ReachResolverTests {
    let notch = CGRect(x: 662, y: 0, width: 188, height: 32)
    let visible = CGRect(x: 0, y: 32, width: 1512, height: 880)

    /// A floating island centered on the given point.
    private func body(_ x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(x: x - 100, y: y - 18, width: 200, height: 36)
    }

    private func target(_ x: CGFloat, _ y: CGFloat, physical: Bool = true) -> ReachTarget? {
        ReachResolver.target(
            body: body(x, y), notch: notch, notchIsPhysical: physical, visibleFrame: visible)
    }

    @Test func nothingIsInReachOutInTheOpen() {
        #expect(target(756, 450) == nil)
        #expect(target(300, 300) == nil)
    }

    @Test func theBottomEdgeIsReachedFromJustAboveIt() {
        // The island's lower side is 60 pt from the edge.
        let found = target(400, 912 - 60 - 18)
        #expect(found?.surface == .edge(.bottom))
        #expect(found?.root == CGPoint(x: 400, y: 912))
        #expect(found?.tangent == CGPoint(x: 1, y: 0))
        // Measured from 12 pt inside the island's side.
        #expect(abs((found?.distance ?? 0) - 72) < 1e-9)
    }

    @Test func reachEndsWhereTheConstantSays() {
        // Island side 67 pt from the top edge: 79 from the hold, just inside the reach.
        #expect(target(300, 32 + 67 + 18)?.surface == .edge(.top))
        // One point further and it is out of reach.
        #expect(target(300, 32 + 69 + 18) == nil)
    }

    @Test func theEdgeNearestTheIslandsSideWinsNotTheOneNearestItsCenter() {
        // The center is nearer the top (90) than the left (110), but the island's left end
        // is 10 pt from the left edge while its top side is 72 pt from the top.
        let found = target(110, 32 + 90)
        #expect(found?.surface == .edge(.left))
        #expect(found?.root == CGPoint(x: 0, y: 122))
        #expect(found?.tangent == CGPoint(x: 0, y: 1))
    }

    @Test func theHoldNeverSpreadsPastACorner() {
        // Pushed into the bottom-left corner, part of it off the display. Both edges are
        // touched; the bottom one is first in the tie-break order.
        let found = target(40, 910)
        #expect(found?.surface == .edge(.bottom))
        #expect(found?.root == CGPoint(x: 80, y: 912))
        #expect(found?.halfSpan == 80)
    }

    @Test func theNotchWinsOverTheEdgeBesideIt() {
        let found = target(756, 80)
        #expect(found?.surface == .notch)
        // Held just inside the lower side of the hardware.
        #expect(found?.root == CGPoint(x: 756, y: 28))
    }

    @Test func theNotchIsReachedWhereverAReleaseWouldReturnToIt() {
        // Beside the notch, under the menu bar: nearer the top edge than the notch's hold,
        // but inside the capture radius, so released here the island goes back to the notch.
        #expect(SnapResolver.anchor(
            forRelease: CGPoint(x: 860, y: 60), notch: notch, visibleFrame: visible) == .notch)
        #expect(target(860, 60)?.surface == .notch)
        // The strands can start from anywhere in that radius, so the main one must hold there.
        for step in 0..<64 {
            let angle = CGFloat(step) / 64 * 2 * .pi
            let x = notch.midX + cos(angle) * SnapResolver.notchCaptureRadius
            let y = max(notch.midY + sin(angle) * SnapResolver.notchCaptureRadius, 18)
            if let found = target(x, y), found.surface == .notch {
                #expect(found.distance < ReachResolver.notchTearDistance - 10)
            }
        }
    }

    @Test func aStandInNotchIsHeldAtTheDisplayEdge() {
        #expect(target(756, 80, physical: false)?.root == CGPoint(x: 756, y: 0))
    }

    @Test func besideTheNotchTheTopEdgeIsReached() {
        #expect(target(1000, 80)?.surface == .edge(.top))
        // Just outside the notch's capture radius.
        #expect(target(900, 60)?.surface == .edge(.top))
    }

    @Test func theHoldRunsTheWayStrandsSpreadAcrossTheIsland() {
        // The simulation spreads strands along the pull direction turned a quarter turn
        // (x, y) -> (-y, x); the pull runs from the surface into the display.
        let inward: [(ReachTarget?, CGPoint)] = [
            (target(300, 80), CGPoint(x: 0, y: 1)),      // top
            (target(400, 880), CGPoint(x: 0, y: -1)),    // bottom
            (target(120, 400), CGPoint(x: 1, y: 0)),     // left
            (target(1400, 400), CGPoint(x: -1, y: 0)),   // right
            (target(756, 80), CGPoint(x: 0, y: 1)),      // notch
        ]
        for (found, pull) in inward {
            #expect(found?.tangent == CGPoint(x: -pull.y, y: pull.x))
        }
    }

    @Test func thinStrandsOutlastTheReach() {
        // Otherwise a strand would shoot out and snap at once.
        #expect(ReachResolver.edgeTearDistance * 0.67 > ReachResolver.edgeReach)
        #expect(ReachResolver.notchTearDistance * 0.67 > ReachResolver.notchReach)
    }

    @Test func strandsLeaveFromTheSideThatFacesTheSurface() {
        func point(_ surface: IslandSurface) -> CGPoint {
            ReachResolver.islandPoint(body: body(500, 400), surface: surface, visibleFrame: visible)
        }
        #expect(point(.edge(.top)) == CGPoint(x: 500, y: 394))
        #expect(point(.edge(.bottom)) == CGPoint(x: 500, y: 406))
        #expect(point(.edge(.left)) == CGPoint(x: 412, y: 400))
        #expect(point(.edge(.right)) == CGPoint(x: 588, y: 400))
        #expect(point(.notch) == CGPoint(x: 500, y: 394))
    }

    @Test func anIslandPushedPastAnEdgeCountsAsPressedAgainstIt() {
        // Carried up over the menu bar: its strands must not be drawn back down across it.
        let overMenuBar = body(300, 16)
        #expect(ReachResolver.islandPoint(
            body: overMenuBar, surface: .edge(.top), visibleFrame: visible) == CGPoint(x: 300, y: 32))
        let found = ReachResolver.target(
            body: overMenuBar, notch: notch, notchIsPhysical: true, visibleFrame: visible)
        #expect(found?.surface == .edge(.top))
        #expect(found?.distance == 0)
    }

    @Test func unusableGeometryReachesNothing() {
        let broken = CGRect(x: CGFloat.nan, y: 0, width: 200, height: 36)
        #expect(ReachResolver.target(
            body: broken, notch: notch, notchIsPhysical: true, visibleFrame: visible) == nil)
        #expect(ReachResolver.target(
            body: body(300, 60), notch: notch, notchIsPhysical: true, visibleFrame: .null) == nil)
    }
}
