import CoreGraphics
import Testing
@testable import SymbiodockCore

struct SymbioteSimulationTests {
    let root = CGPoint(x: 260, y: 16)

    func island(at distance: CGFloat) -> CGPoint {
        CGPoint(x: root.x, y: root.y + distance)
    }

    /// Holds the island still at `distance` for `seconds`.
    func hold(_ simulation: inout SymbioteSimulation, at distance: CGFloat, for seconds: Double, fps: Double = 60) {
        for _ in 0..<Int((seconds * fps).rounded()) {
            simulation.advance(root: root, island: island(at: distance), dt: 1 / fps)
        }
    }

    @Test func nothingToDrawBeforeTheFirstInput() {
        let simulation = SymbioteSimulation()
        #expect(simulation.frame.isEmpty)
        #expect(!simulation.isTorn)
        #expect(!simulation.isFinished)
    }

    @Test func aShortPullDrawsOneRibbonPerStrand() {
        var simulation = SymbioteSimulation()
        hold(&simulation, at: 40, for: 0.5)

        let frame = simulation.frame
        #expect(frame.ribbons.count == 5)
        #expect(frame.droplets.isEmpty)
        #expect(frame.ribbons.allSatisfy { polygon in
            polygon.count >= 6 && polygon.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        })
    }

    @Test func mainStrandTearsExactlyPastTheTearDistance() {
        var simulation = SymbioteSimulation()
        hold(&simulation, at: 120, for: 1)
        #expect(!simulation.isTorn)

        simulation.advance(root: root, island: island(at: 120.5), dt: 1.0 / 60)
        #expect(simulation.isTorn)
    }

    @Test func thinStrandsTearBeforeTheMainOne() {
        var simulation = SymbioteSimulation()
        hold(&simulation, at: 100, for: 0.2)

        #expect(!simulation.isTorn)
        // Torn strands show as stubs with a bead at the tip.
        #expect(!simulation.frame.droplets.isEmpty)
    }

    @Test func neckRadiusNeverGrowsWithDistance() {
        var previous = CGFloat.infinity
        for step in 0...400 {
            let radius = SymbioteSimulation.neckRadius(
                distance: CGFloat(step) * 0.5, endRadius: 15, tearDistance: 120)
            #expect(radius <= previous)
            #expect(radius > 0)
            previous = radius
        }
    }

    @Test func everythingSnapsBackAndDisappearsAfterTheTear() {
        var simulation = SymbioteSimulation()
        hold(&simulation, at: 130, for: 1.5)

        #expect(simulation.isTorn)
        #expect(simulation.isFinished)
        #expect(simulation.frame.isEmpty)
    }

    @Test func sameInputsGiveTheSameFrames() {
        var first = SymbioteSimulation()
        var second = SymbioteSimulation()
        for step in 0..<90 {
            let point = CGPoint(x: root.x + CGFloat(step), y: root.y + CGFloat(step) * 1.6)
            first.advance(root: root, island: point, dt: 1.0 / 60)
            second.advance(root: root, island: point, dt: 1.0 / 60)
            #expect(first.frame == second.frame)
        }
    }

    @Test func resultDoesNotDependOnTheFrameRate() {
        var slow = SymbioteSimulation()
        var fast = SymbioteSimulation()
        hold(&slow, at: 80, for: 1, fps: 60)
        hold(&fast, at: 80, for: 1, fps: 120)

        let a = slow.frame.ribbons.flatMap { $0 }
        let b = fast.frame.ribbons.flatMap { $0 }
        #expect(a.count == b.count)
        for (p, q) in zip(a, b) {
            #expect(abs(p.x - q.x) < 0.01 && abs(p.y - q.y) < 0.01)
        }
    }

    @Test func aLongHitchDoesNotBlowUp() {
        var simulation = SymbioteSimulation()
        simulation.advance(root: root, island: island(at: 10), dt: 1.0 / 60)
        simulation.advance(root: root, island: island(at: 90), dt: 5)

        #expect(simulation.frame.ribbons.flatMap { $0 }.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test func attachmentsStayInsideTheirSpreadWhateverTheDirection() {
        var simulation = SymbioteSimulation()
        let sideways = CGPoint(x: root.x + 60, y: root.y)
        simulation.advance(root: root, island: sideways, dt: 1.0 / 60)

        // Pulled sideways, strands spread vertically, limited by the bodies' height (7 and 9 pt).
        let ys = simulation.frame.ribbons.flatMap { $0 }.map(\.y)
        #expect((ys.min() ?? 0) > root.y - 30)
        #expect((ys.max() ?? 0) < root.y + 30)
    }
}
