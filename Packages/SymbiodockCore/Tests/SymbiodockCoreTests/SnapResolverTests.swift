import CoreGraphics
import Testing
@testable import SymbiodockCore

struct SnapResolverTests {
    let notch = CGRect(x: 662, y: 0, width: 188, height: 32)
    let visible = CGRect(x: 0, y: 32, width: 1512, height: 880)

    private func resolve(_ x: CGFloat, _ y: CGFloat) -> IslandAnchor {
        SnapResolver.anchor(forRelease: CGPoint(x: x, y: y), notch: notch, visibleFrame: visible)
    }

    private func expectEdge(
        _ anchor: IslandAnchor, _ edge: ScreenEdge, _ fraction: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .edge(let actualEdge, let actualFraction) = anchor else {
            Issue.record("expected an edge anchor, got \(anchor)", sourceLocation: sourceLocation)
            return
        }
        #expect(actualEdge == edge, sourceLocation: sourceLocation)
        #expect(abs(actualFraction - fraction) < 1e-9, sourceLocation: sourceLocation)
    }

    @Test func releaseNearTheNotchReturnsToIt() {
        #expect(resolve(756, 100) == .notch)
    }

    @Test func notchCaptureBoundaryIsInclusive() {
        #expect(resolve(756, 136) == .notch)
        #expect(resolve(756, 137) != .notch)
    }

    @Test func eachCornerCaptures() {
        #expect(resolve(30, 60) == .corner(.topLeft))
        #expect(resolve(1490, 60) == .corner(.topRight))
        #expect(resolve(30, 890) == .corner(.bottomLeft))
        #expect(resolve(1490, 890) == .corner(.bottomRight))
    }

    @Test func cornerCaptureBoundaryIsInclusive() {
        #expect(resolve(80, 32) == .corner(.topLeft))
        expectEdge(resolve(81, 32), .top, 81.0 / 1512)
    }

    @Test func nearestEdgeWins() {
        expectEdge(resolve(400, 300), .top, 400.0 / 1512)
        expectEdge(resolve(400, 800), .bottom, 400.0 / 1512)
        expectEdge(resolve(100, 500), .left, 468.0 / 880)
        expectEdge(resolve(1400, 500), .right, 468.0 / 880)
    }

    @Test func pointOutsideTheVisibleFrameIsClamped() {
        expectEdge(resolve(-50, 500), .left, 468.0 / 880)
        expectEdge(resolve(700, 1000), .bottom, 700.0 / 1512)
    }

    // MARK: Degenerate input

    @Test func nonFinitePointReturnsToTheNotch() {
        #expect(resolve(.nan, 300) == .notch)
        #expect(resolve(400, .infinity) == .notch)
        #expect(resolve(-.infinity, .nan) == .notch)
    }

    @Test func farOutsidePointIsClampedBeforeTheEdgeAndCornerRules() {
        // (2000, 500) clamps to (1512, 500): on the right edge, mid-height.
        expectEdge(resolve(2000, 500), .right, 468.0 / 880)
        // Far past a corner clamps onto it.
        #expect(resolve(5000, 5000) == .corner(.bottomRight))
        #expect(resolve(-900, 40) == .corner(.topLeft))
    }

    @Test func fractionThatNeedsTheClampIsClamped() {
        let narrow = CGRect(x: 100, y: 32, width: 400, height: 880)
        let anchor = SnapResolver.anchor(
            forRelease: CGPoint(x: 5000, y: 500), notch: notch, visibleFrame: narrow)
        guard case .edge(.right, let fraction) = anchor else {
            Issue.record("expected the right edge, got \(anchor)")
            return
        }
        #expect(fraction >= 0 && fraction <= 1)
    }

    @Test func notchCaptureUsesTheRawPoint() {
        let outside = CGRect(x: 0, y: 400, width: 1512, height: 500)
        // Raw point is on the notch; clamping into `outside` would have moved it away.
        #expect(
            SnapResolver.anchor(
                forRelease: CGPoint(x: 756, y: 20), notch: notch, visibleFrame: outside) == .notch)
    }

    @Test func zeroSizedVisibleFrameStillGivesAValidAnchor() {
        let point = CGPoint(x: 900, y: 900)
        let flat = CGRect(x: 0, y: 100, width: 0, height: 0)
        #expect(
            SnapResolver.anchor(forRelease: point, notch: notch, visibleFrame: flat)
                == .corner(.topLeft))

        // A vertical sliver: the left edge wins and the fraction runs along the height.
        let sliver = CGRect(x: 500, y: 100, width: 0, height: 500)
        expectEdge(
            SnapResolver.anchor(
                forRelease: CGPoint(x: 500, y: 300), notch: notch, visibleFrame: sliver),
            .left, 0.4)
    }

    @Test func unusableVisibleFrameReturnsToTheNotch() {
        #expect(
            SnapResolver.anchor(forRelease: CGPoint(x: 900, y: 900), notch: notch, visibleFrame: .null)
                == .notch)
    }

    // MARK: Released while strands hold a surface

    private func resolve(_ x: CGFloat, _ y: CGFloat, heldBy surface: IslandSurface?) -> IslandAnchor {
        SnapResolver.anchor(
            forRelease: CGPoint(x: x, y: y), attachedTo: surface, notch: notch, visibleFrame: visible)
    }

    @Test func withNoHoldTheNearestPlaceRuleApplies() {
        #expect(resolve(756, 100, heldBy: nil) == resolve(756, 100))
        #expect(resolve(300, 700, heldBy: nil) == resolve(300, 700))
    }

    @Test func aHeldNotchTakesTheIslandBackEvenFromOutsideItsCaptureRadius() {
        #expect(resolve(756, 190) != .notch)
        #expect(resolve(756, 190, heldBy: .notch) == .notch)
    }

    @Test func aHeldEdgeWinsOverANearerOne() {
        // The center is nearer the top, but the strands hold the left edge.
        expectEdge(resolve(110, 122), .top, 110.0 / 1512)
        expectEdge(resolve(110, 122 + 400, heldBy: .edge(.left)), .left, 490.0 / 880)
    }

    @Test func aHeldEdgeWinsOverTheNotchCapture() {
        expectEdge(resolve(756, 100, heldBy: .edge(.top)), .top, 0.5)
    }

    @Test func nearTheEndOfAHeldEdgeTheIslandGoesToThatCorner() {
        #expect(resolve(60, 500, heldBy: .edge(.bottom)) == .corner(.bottomLeft))
        #expect(resolve(1500, 500, heldBy: .edge(.bottom)) == .corner(.bottomRight))
        #expect(resolve(700, 60, heldBy: .edge(.right)) == .corner(.topRight))
        expectEdge(resolve(200, 500, heldBy: .edge(.bottom)), .bottom, 200.0 / 1512)
    }

    @Test func aHeldEdgeWithABrokenPointFallsBackToTheNotch() {
        #expect(resolve(.nan, 100, heldBy: .edge(.top)) == .notch)
    }
}
