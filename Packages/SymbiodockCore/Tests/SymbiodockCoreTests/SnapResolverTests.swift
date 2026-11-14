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
}
