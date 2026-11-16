import CoreGraphics
import Testing
@testable import SymbiodockCore

struct SymbioteEngulfTests {
    private let size = CGSize(width: 64, height: 96)

    private func cover(_ phase: EngulfPhase, _ size: CGSize? = nil) -> Double {
        let size = size ?? self.size
        return SymbioteEngulf.coverage(of: SymbioteEngulf.frame(size: size, phase: phase), size: size)
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
    }

    @Test func theEngulfOnlyEverCloses() {
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { cover(.engulf($0)) }
        for (earlier, later) in zip(steps, steps.dropFirst()) { #expect(later >= earlier - 0.005) }
    }

    @Test func theRevealOnlyEverOpens() {
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { cover(.reveal($0)) }
        for (earlier, later) in zip(steps, steps.dropFirst()) { #expect(later <= earlier + 0.005) }
    }

    @Test func halfwayItIsStrandsNotAFade() {
        let frame = SymbioteEngulf.frame(size: size, phase: .engulf(0.5))
        #expect((0.15...0.9).contains(cover(.engulf(0.5))))
        #expect(frame.ribbons.count >= 6)
        #expect(!frame.droplets.isEmpty)
        #expect((0.1...0.9).contains(cover(.reveal(0.5))))
    }

    @Test func theGooStaysByTheTile() {
        let allowed = CGRect(origin: .zero, size: size)
            .insetBy(dx: -SymbioteEngulf.overhang, dy: -SymbioteEngulf.overhang)
        for phase in [EngulfPhase.engulf(0.3), .engulf(0.8), .cocoon, .reveal(0.2), .reveal(0.7)] {
            let frame = SymbioteEngulf.frame(size: size, phase: phase)
            let box = try! #require(frame.boundingBox)
            #expect(allowed.contains(box))
            #expect(frame.ribbons.allSatisfy { $0.count >= 3 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } })
        }
    }

    @Test func theCocoonGlints() {
        #expect(!SymbioteEngulf.frame(size: size, phase: .cocoon).highlights.isEmpty)
    }

    @Test func theSameMomentIsTheSameFrame() {
        #expect(
            SymbioteEngulf.frame(size: size, phase: .engulf(0.42))
                == SymbioteEngulf.frame(size: size, phase: .engulf(0.42)))
    }
}
