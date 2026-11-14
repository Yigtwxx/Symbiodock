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

    // MARK: Reaching for a surface

    /// A simulation whose strands grow out of the island toward a flat surface along y = 16.
    func reaching() -> SymbioteSimulation {
        var configuration = SymbioteSimulation.Configuration()
        configuration.tearDistance = 130
        configuration.rootSpan = CGPoint(x: 80, y: 0)
        return SymbioteSimulation(configuration: configuration, reaching: true)
    }

    /// Smallest distance from any drawn point to the surface.
    func gapToSurface(_ frame: SymbioteFrame) -> CGFloat {
        let ys = frame.ribbons.flatMap { $0 }.map(\.y) + frame.droplets.map { $0.center.y - $0.radius }
        return (ys.min() ?? .infinity) - root.y
    }

    @Test func aReachingSimulationStartsWithNothingOnTheSurface() {
        var simulation = reaching()
        simulation.advance(root: root, island: island(at: 70), dt: 1.0 / 60)

        #expect(!simulation.isTorn)
        #expect(!simulation.isHolding)
        #expect(!simulation.isFinished)
        // Whatever has left the island is still far from the surface.
        #expect(gapToSurface(simulation.frame) > 40)
    }

    @Test func feelersGrowTowardTheSurface() {
        var simulation = reaching()
        var previous = CGFloat.infinity
        for _ in 0..<8 {
            simulation.advance(root: root, island: island(at: 70), dt: 1.0 / 60)
            let gap = gapToSurface(simulation.frame)
            #expect(gap <= previous + 0.5)
            previous = gap
        }
        #expect(previous < 20)
        // Feelers carry a bead at the tip.
        #expect(!simulation.frame.droplets.isEmpty)
    }

    @Test func everyStrandLandsAndHolds() {
        var simulation = reaching()
        hold(&simulation, at: 70, for: 0.6)

        #expect(simulation.isHolding)
        #expect(!simulation.isTorn)
        let frame = simulation.frame
        // Ten strands, and the mound each one spreads into where it holds the surface.
        #expect(frame.ribbons.count == 20)
        #expect(frame.droplets.isEmpty)
        // Every strand ends flat on the surface: nothing is drawn past it.
        #expect(abs(gapToSurface(frame)) < 0.01)
    }

    @Test func thinFeelersLandBeforeTheTrunk() {
        var simulation = reaching()
        hold(&simulation, at: 70, for: 0.2)

        #expect(!simulation.isHolding)
        // Some strands are on the surface already.
        #expect(gapToSurface(simulation.frame) < 2)
    }

    @Test func aSurfaceIsHeldAlongItselfHoweverTheIslandIsPulled() {
        var simulation = reaching()
        // Dragged diagonally away from the hold.
        let diagonal = CGPoint(x: root.x + 60, y: root.y + 60)
        for _ in 0..<40 { simulation.advance(root: root, island: diagonal, dt: 1.0 / 60) }

        #expect(simulation.isHolding)
        // No strand ends above the surface, where a rotated spread would put some.
        #expect(gapToSurface(simulation.frame) > -16)
        let xs = simulation.frame.ribbons.flatMap { $0 }.filter { $0.y < root.y + 3 }.map(\.x)
        #expect((xs.min() ?? 0) < root.x - 40)
        #expect((xs.max() ?? 0) > root.x + 40)
    }

    @Test func heldStrandsTearLikeAnyOthers() {
        var simulation = reaching()
        hold(&simulation, at: 70, for: 0.6)
        hold(&simulation, at: 131, for: 0.1)
        #expect(simulation.isTorn)
        #expect(!simulation.isHolding)
        hold(&simulation, at: 131, for: 0.6)
        #expect(simulation.isFinished)
    }

    @Test func feelersPulledOutOfRangeAreDrawnBackIn() {
        var simulation = reaching()
        hold(&simulation, at: 70, for: 0.05)
        hold(&simulation, at: 140, for: 0.05)

        #expect(simulation.isTorn)
        #expect(!simulation.isHolding)
        hold(&simulation, at: 140, for: 0.7)
        #expect(simulation.isFinished)
        #expect(simulation.frame.isEmpty)
    }

    @Test func tearCallsBackFeelersThatHaveNotLanded() {
        var simulation = reaching()
        hold(&simulation, at: 70, for: 0.1)
        simulation.tear()

        #expect(simulation.isTorn)
        hold(&simulation, at: 70, for: 0.7)
        #expect(simulation.isFinished)
    }

    @Test func thicknessScalesEveryStrand() {
        func width(_ thickness: CGFloat) -> CGFloat {
            var simulation = reaching()
            hold(&simulation, at: 70, for: 0.6)
            simulation.thickness = thickness
            // A ribbon is one side forward and the other back: these two points face each
            // other across the main strand, half way along it.
            let polygon = simulation.frame.ribbons[0]
            let near = polygon[polygon.count / 4]
            let far = polygon[polygon.count - 1 - polygon.count / 4]
            return hypot(near.x - far.x, near.y - far.y)
        }
        #expect(width(1) > 4)
        #expect(abs(width(0.5) - width(1) / 2) < 0.6)
        #expect(width(0.1) < width(0.5))
    }

    @Test func reachingIsDeterministic() {
        func run() -> SymbioteFrame {
            var simulation = reaching()
            hold(&simulation, at: 60, for: 0.17)
            return simulation.frame
        }
        #expect(run() == run())
    }

    @Test func framesAddUpAndReportTheirBounds() {
        var first = SymbioteFrame(ribbons: [[CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 4)]])
        let second = SymbioteFrame(droplets: [.init(center: CGPoint(x: 30, y: 30), radius: 5)])
        #expect(SymbioteFrame().boundingBox == nil)

        first.append(second)
        #expect(first.ribbons.count == 1)
        #expect(first.droplets.count == 1)
        #expect(first.boundingBox == CGRect(x: 0, y: 0, width: 35, height: 35))
    }

    @Test func tearBeforeTheFirstInputDoesNotCrash() {
        var simulation = reaching()
        simulation.tear()
        #expect(simulation.isTorn)
        #expect(simulation.isFinished)
        #expect(simulation.frame.isEmpty)
    }

    @Test func strandsOutOfTheirOwnRangeWaitForTheIslandToComeCloser() {
        var simulation = reaching()
        // 110 pt: within the main strand's range (130), beyond the thin ones' (87).
        hold(&simulation, at: 110, for: 0.6)
        #expect(simulation.isHolding)
        // Strands and their mounds come in pairs once landed.
        let far = simulation.frame.ribbons.count
        #expect(far >= 2 && far < 20)

        hold(&simulation, at: 60, for: 0.6)
        #expect(simulation.frame.ribbons.count == 20)
    }

    @Test func fullySoakedUpStrandsDrawNothingAtAll() {
        var simulation = reaching()
        hold(&simulation, at: 70, for: 0.6)
        #expect(!simulation.frame.highlights.isEmpty)

        simulation.thickness = 0
        #expect(simulation.frame.isEmpty)
        #expect(simulation.frame.highlights.isEmpty)
    }
}
