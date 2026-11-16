import CoreGraphics
import Testing
@testable import SymbiodockCore

struct SymbioteEngulfTests {
    private let size = CGSize(width: 64, height: 96)
    /// A drawer's box: a tile plus the tabs of the cards behind.
    private let stack = CGSize(width: 64, height: 104)

    private func cover(_ phase: EngulfPhase, _ size: CGSize? = nil) -> Double {
        let size = size ?? self.size
        return SymbioteEngulf.coverage(of: SymbioteEngulf.frame(size: size, phase: phase), size: size)
    }

    /// Whether `point` of the tile lies under goo at `phase`: the coverage of a one-point tile
    /// sampled once, with the frame moved so that `point` falls on that sample.
    private func isCovered(_ point: CGPoint, _ phase: EngulfPhase) -> Bool {
        let frame = SymbioteEngulf.frame(size: size, phase: phase)
        func moved(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - point.x + 0.5, y: p.y - point.y + 0.5) }
        let shifted = SymbioteFrame(
            ribbons: frame.ribbons.map { $0.map(moved) },
            droplets: frame.droplets.map { .init(center: moved($0.center), radius: $0.radius) })
        return SymbioteEngulf.coverage(of: shifted, size: CGSize(width: 1, height: 1), step: 1) == 1
    }

    @Test func nothingIsDrawnBeforeAndAfter() {
        #expect(SymbioteEngulf.frame(size: size, phase: .engulf(0)).isEmpty)
        #expect(SymbioteEngulf.frame(size: size, phase: .reveal(1)).isEmpty)
        #expect(SymbioteEngulf.frame(size: size, phase: .done).isEmpty)
    }

    @Test func theCocoonHidesTheWholeTile() {
        #expect(cover(.engulf(1)) == 1)
        #expect(cover(.cocoon) == 1)
        #expect(cover(.reveal(0)) == 1)
        #expect(cover(.cocoon, CGSize(width: 48, height: 48)) == 1)
        #expect(cover(.cocoon, stack) == 1)
    }

    @Test func itIsClosedBeforeTheCoverRectangleComesIn() {
        // Nothing pops shut at the end of the closing.
        #expect(cover(.engulf(0.95)) == 1)
        #expect(cover(.engulf(0.95), stack) == 1)
    }

    @Test(arguments: [CGSize(width: 64, height: 96), CGSize(width: 64, height: 104)])
    func theEngulfOnlyEverCloses(_ size: CGSize) {
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { cover(.engulf($0), size) }
        for (earlier, later) in zip(steps, steps.dropFirst()) { #expect(later >= earlier - 0.005) }
    }

    @Test(arguments: [CGSize(width: 64, height: 96), CGSize(width: 64, height: 104)])
    func theRevealOnlyEverOpens(_ size: CGSize) {
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { cover(.reveal($0), size) }
        for (earlier, later) in zip(steps, steps.dropFirst()) { #expect(later <= earlier + 0.005) }
    }

    @Test func halfwayItIsStrandsNotAFade() {
        let frame = SymbioteEngulf.frame(size: size, phase: .engulf(0.5))
        #expect((0.15...0.9).contains(cover(.engulf(0.5))))
        #expect(frame.ribbons.count >= 6)
        #expect(!frame.droplets.isEmpty)
        #expect((0.1...0.9).contains(cover(.reveal(0.5))))
    }

    @Test func theGooComesInFromTheEdges() {
        // Early on the strands hold the edges and the middle is still open.
        let early = EngulfPhase.engulf(0.25)
        #expect(!isCovered(CGPoint(x: 32, y: 48), early))
        let edge = (0..<24).map { CGPoint(x: 0.5, y: 2 + CGFloat($0) * 4) }
            + (0..<16).map { CGPoint(x: 2 + CGFloat($0) * 4, y: 0.5) }
        #expect(edge.contains { isCovered($0, early) })
    }

    @Test func theCoverTearsInTheMiddleFirst() {
        // Early in the reveal the middle shows through while the corners are still covered.
        let early = EngulfPhase.reveal(0.15)
        #expect(!isCovered(CGPoint(x: 32, y: 40), early))
        for corner in [CGPoint(x: 1, y: 1), CGPoint(x: 63, y: 1), CGPoint(x: 1, y: 95), CGPoint(x: 63, y: 95)] {
            #expect(isCovered(corner, early))
        }
    }

    @Test func theGooStaysByTheTile() throws {
        let allowed = CGRect(origin: .zero, size: size)
            .insetBy(dx: -SymbioteEngulf.overhang, dy: -SymbioteEngulf.overhang)
        for phase in [EngulfPhase.engulf(0.3), .engulf(0.8), .cocoon, .reveal(0.2), .reveal(0.7)] {
            let frame = SymbioteEngulf.frame(size: size, phase: phase)
            let box = try #require(frame.boundingBox)
            #expect(allowed.contains(box))
            #expect(frame.ribbons.allSatisfy { $0.count >= 3 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
        }
    }

    @Test(arguments: [CGSize(width: 64, height: 96), CGSize(width: 64, height: 104)])
    func theGooNeverReachesTheNextTile(_ size: CGSize) {
        // Tiles stand 8 pt apart; the goo keeps to its half of the gap, beads included.
        let allowed = CGRect(origin: .zero, size: size)
            .insetBy(dx: -SymbioteEngulf.margin - 0.01, dy: -SymbioteEngulf.margin - 0.01)
        let phases = (1..<100).flatMap { [EngulfPhase.engulf(Double($0) / 100), .reveal(Double($0) / 100)] }
        for phase in phases {
            let frame = SymbioteEngulf.frame(size: size, phase: phase)
            #expect(frame.ribbons.allSatisfy { $0.allSatisfy(allowed.contains) })
            #expect(frame.droplets.allSatisfy {
                allowed.contains(CGRect(
                    x: $0.center.x - $0.radius, y: $0.center.y - $0.radius,
                    width: 2 * $0.radius, height: 2 * $0.radius))
            })
        }
    }

    @Test func theCocoonGlints() {
        #expect(!SymbioteEngulf.frame(size: size, phase: .cocoon).highlights.isEmpty)
    }

    @Test func theSameMomentIsTheSameFrame() {
        #expect(
            SymbioteEngulf.frame(size: size, phase: .engulf(0.42))
                == SymbioteEngulf.frame(size: size, phase: .engulf(0.42)))
        #expect(
            SymbioteEngulf.frame(size: size, phase: .reveal(0.42))
                == SymbioteEngulf.frame(size: size, phase: .reveal(0.42)))
    }

    @Test func aTileWithoutASizeHasNoGoo() {
        for broken in [CGSize.zero, CGSize(width: -64, height: 96), CGSize(width: CGFloat.nan, height: 96),
                       CGSize(width: 64, height: CGFloat.infinity)] {
            #expect(SymbioteEngulf.frame(size: broken, phase: .cocoon).isEmpty)
            #expect(SymbioteEngulf.frame(size: broken, phase: .engulf(0.5)).isEmpty)
            #expect(SymbioteEngulf.frame(size: broken, phase: .reveal(0.5)).isEmpty)
        }
        let cocoon = SymbioteEngulf.frame(size: size, phase: .cocoon)
        #expect(SymbioteEngulf.coverage(of: cocoon, size: .zero) == 0)
        #expect(SymbioteEngulf.coverage(of: cocoon, size: size, step: 0) == 0)
    }

    @Test func progressOutsideItsRangeHoldsAtTheEnds() {
        let cocoon = SymbioteEngulf.frame(size: size, phase: .cocoon)
        #expect(SymbioteEngulf.frame(size: size, phase: .engulf(-0.5)).isEmpty)
        #expect(SymbioteEngulf.frame(size: size, phase: .engulf(.nan)).isEmpty)
        #expect(SymbioteEngulf.frame(size: size, phase: .engulf(1.5)) == cocoon)
        #expect(SymbioteEngulf.frame(size: size, phase: .reveal(-0.5)) == cocoon)
        #expect(SymbioteEngulf.frame(size: size, phase: .reveal(1.5)).isEmpty)
        #expect(SymbioteEngulf.frame(size: size, phase: .reveal(.nan)).isEmpty)
    }
}
