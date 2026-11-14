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
        #expect(frame.ribbons.count == 10)
        // Only the thicker strands carry a sheen.
        #expect(!frame.highlights.isEmpty)
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

    /// Moves the island along `position(t)` for `seconds`, one `advance` per display frame.
    func follow(
        _ simulation: inout SymbioteSimulation, fps: Double, seconds: Double,
        position: (Double) -> CGPoint
    ) {
        let frames = Int((seconds * fps).rounded())
        for frame in 1...frames {
            let t = Double(frame) / fps
            simulation.advance(root: root, island: position(t), dt: 1 / fps)
        }
    }

    @Test func resultDoesNotDependOnTheFrameRate() {
        // Distances stay below the first strand's tear distance (about 88 pt).
        let path: (Double) -> CGPoint = { t in
            CGPoint(x: root.x + 20 * sin(t * 3), y: root.y + 20 + 55 * t)
        }
        var slow = SymbioteSimulation()
        var fast = SymbioteSimulation()
        follow(&slow, fps: 60, seconds: 1, position: path)
        follow(&fast, fps: 144, seconds: 1, position: path)

        let a = slow.frame.ribbons.flatMap { $0 }
        let b = fast.frame.ribbons.flatMap { $0 }
        #expect(a.count == b.count)
        #expect(!a.isEmpty)
        for (p, q) in zip(a, b) {
            #expect(abs(p.x - q.x) < 0.5 && abs(p.y - q.y) < 0.5)
        }
    }

    @Test func mainStrandGetsNarrowerAtItsMiddleAsTheDistanceGrows() {
        func middleWidth(at distance: CGFloat) -> CGFloat {
            var simulation = SymbioteSimulation()
            hold(&simulation, at: distance, for: 1)
            let polygon = simulation.frame.ribbons[0]
            let middle = SymbioteSimulation.sampleCount / 2
            let p = polygon[middle]
            let q = polygon[polygon.count - 1 - middle]
            return hypot(p.x - q.x, p.y - q.y)
        }
        let near = middleWidth(at: 30)
        let mid = middleWidth(at: 60)
        let far = middleWidth(at: 90)
        #expect(near > mid)
        #expect(mid > far)
        #expect(far > 0)
    }

    // MARK: Forced tear

    @Test func tearBreaksEveryAttachedStrandAtOnce() {
        var simulation = SymbioteSimulation()
        hold(&simulation, at: 40, for: 0.3)
        #expect(!simulation.isTorn)

        simulation.tear()
        #expect(simulation.isTorn)

        hold(&simulation, at: 40, for: 1.5)
        #expect(simulation.isFinished)
        #expect(simulation.frame.isEmpty)
    }

    @Test func tearLeavesStrandsThatAreAlreadyBreakingAlone() {
        var torn = SymbioteSimulation()
        hold(&torn, at: 100, for: 0.2)
        var twice = torn
        twice.tear()
        var again = twice
        again.tear()
        #expect(twice.frame == again.frame)

        var finished = SymbioteSimulation()
        hold(&finished, at: 130, for: 1.5)
        #expect(finished.isFinished)
        finished.tear()
        #expect(finished.isFinished)
        #expect(finished.frame.isEmpty)
    }

    @Test func tearBeforeAnyInputIsHarmless() {
        var simulation = SymbioteSimulation()
        simulation.tear()
        #expect(simulation.frame.isEmpty)
        hold(&simulation, at: 20, for: 1.5)
        #expect(simulation.isFinished)
    }

    // MARK: Bad input

    @Test func nonFiniteInputIsIgnored() {
        var simulation = SymbioteSimulation()
        hold(&simulation, at: 50, for: 0.3)
        let before = simulation.frame

        simulation.advance(root: root, island: island(at: 60), dt: Double.nan)
        simulation.advance(root: root, island: island(at: 60), dt: Double.infinity)
        simulation.advance(root: root, island: CGPoint(x: CGFloat.nan, y: 10), dt: 1.0 / 60)
        simulation.advance(root: CGPoint(x: 1, y: CGFloat.infinity), island: island(at: 60), dt: 1.0 / 60)
        #expect(simulation.frame == before)

        hold(&simulation, at: 130, for: 1.5)
        #expect(simulation.isTorn)
        #expect(simulation.isFinished)
    }

    @Test func nonFiniteFirstInputDoesNotStartTheSimulation() {
        var simulation = SymbioteSimulation()
        simulation.advance(root: root, island: CGPoint(x: CGFloat.nan, y: CGFloat.nan), dt: 1.0 / 60)
        #expect(simulation.frame.isEmpty)
        hold(&simulation, at: 130, for: 1.5)
        #expect(simulation.isFinished)
    }

    // MARK: Public construction

    @Test func framesCanBeBuiltByTheApp() {
        let frame = SymbioteFrame(
            ribbons: [[.zero, CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 0)]],
            droplets: [.init(center: CGPoint(x: 3, y: 3), radius: 2)])
        #expect(!frame.isEmpty)
        #expect(SymbioteFrame().isEmpty)
    }

    @Test func stubsAreGoneAsSoonAsTheyAreBackInTheirBodies() {
        var simulation = SymbioteSimulation()
        hold(&simulation, at: 130, for: 0.1)
        #expect(simulation.isTorn)
        // The recoil settles well before its 0.6 s upper bound.
        hold(&simulation, at: 130, for: 0.4)
        #expect(simulation.isFinished)
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
