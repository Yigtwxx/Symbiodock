import CoreGraphics
import Foundation

/// What the renderer draws for one instant: goo shapes only, never the island or the root.
public struct SymbioteFrame: Equatable, Sendable {
    public struct Droplet: Equatable, Sendable {
        public var center: CGPoint
        public var radius: CGFloat
    }

    /// Closed polygons, one per strand or stub.
    public var ribbons: [[CGPoint]] = []
    public var droplets: [Droplet] = []

    public var isEmpty: Bool { ribbons.isEmpty && droplets.isEmpty }
}

/// Sticky strands between the place the island was attached (the root) and the island.
///
/// Pure and deterministic: the same sequence of `advance` calls always gives the same frames.
/// Strands lag behind the pointer like syrup, thin out as they stretch, pinch off past their
/// tear distance (thin ones first), and the two halves snap back into their bodies.
public struct SymbioteSimulation: Sendable {
    public struct Configuration: Equatable, Sendable {
        /// Distance at which the main strand tears.
        public var tearDistance: CGFloat = 120
        /// Half the size of the area inside each body over which strands attach.
        public var rootSpread = CGSize(width: 62, height: 7)
        public var islandSpread = CGSize(width: 70, height: 9)
        /// Radius of the main strand where it meets a body.
        public var endRadius: CGFloat = 15

        public init() {}
    }

    // MARK: Tuning

    static let substep = 1.0 / 240
    static let maxFrameTime = 1.0 / 30
    static let pinchDuration = 0.07
    static let recoilDuration = 0.6
    static let nodeCount = 6
    static let sampleCount = 24
    /// Chord length at which a strand has its full thickness.
    static let restLength: CGFloat = 30
    static let minimumNeckRadius: CGFloat = 1.3

    private struct Blueprint {
        var weight: CGFloat      // thickness relative to the main strand
        var offset: CGFloat      // attachment position across the bodies, -1...1
        var tearScale: CGFloat   // fraction of the tear distance at which this strand goes
        var neck: CGFloat        // where along the strand it breaks, 0...1
        var bow: CGFloat         // slack sideways sag while short
    }

    private static let blueprints: [Blueprint] = [
        Blueprint(weight: 1.00, offset: 0.06, tearScale: 1.00, neck: 0.50, bow: 0.15),
        Blueprint(weight: 0.70, offset: -0.50, tearScale: 0.94, neck: 0.44, bow: -1.0),
        Blueprint(weight: 0.56, offset: 0.62, tearScale: 0.88, neck: 0.57, bow: 1.0),
        Blueprint(weight: 0.40, offset: -0.20, tearScale: 0.82, neck: 0.52, bow: -0.5),
        Blueprint(weight: 0.30, offset: 0.34, tearScale: 0.74, neck: 0.46, bow: 0.7),
    ]

    private struct Node: Sendable {
        var position: CGPoint
        var velocity: CGPoint = .zero
    }

    private struct Recoil: Sendable {
        var rootLength: CGFloat
        var islandLength: CGFloat
        var rootDirection: CGPoint
        var islandDirection: CGPoint
        var tipRadius: CGFloat
        var progress: Double = 0
        var speed: Double = 0
    }

    private enum Phase: Sendable {
        case attached
        case pinching(elapsed: Double)
        case recoiling(elapsed: Double, Recoil)
        case gone
    }

    private struct Strand: Sendable {
        var nodes: [Node] = []
        var phase: Phase = .attached
    }

    // MARK: State

    public let configuration: Configuration
    private var strands: [Strand]
    private var root: CGPoint = .zero
    private var island: CGPoint = .zero
    private var accumulator = 0.0
    private var hasInput = false

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        strands = Self.blueprints.map { _ in Strand() }
    }

    /// True from the step on which the main strand starts to break.
    public var isTorn: Bool {
        if case .attached = strands[0].phase { return false }
        return true
    }

    /// True when every strand has torn and finished snapping back: nothing is left to draw.
    public var isFinished: Bool {
        strands.allSatisfy { if case .gone = $0.phase { return true } else { return false } }
    }

    /// Radius of a strand's thinnest point when its ends are `distance` apart.
    /// Never grows with distance: the further the pull, the thinner the neck.
    public static func neckRadius(
        distance: CGFloat, endRadius: CGFloat, tearDistance: CGFloat
    ) -> CGFloat {
        let d = max(distance, 0)
        // A bridge of constant volume gets thinner as it gets longer.
        let conserved = 0.8 * endRadius * (restLength / (restLength + d)).squareRoot()
        // Close to the tear distance thinning runs away.
        let late = 1 - 0.7 * smoothstep(0.8, 1.0, d / max(tearDistance, 1))
        return max(conserved * late, minimumNeckRadius)
    }

    // MARK: Stepping

    /// Moves the simulation forward by `dt` seconds with the bodies at the given points.
    public mutating func advance(root: CGPoint, island: CGPoint, dt: Double) {
        self.root = root
        self.island = island
        if !hasInput {
            hasInput = true
            for index in strands.indices { strands[index].nodes = restNodes(index) }
        }
        accumulator += min(max(dt, 0), Self.maxFrameTime)
        // Fixed steps keep the result independent of the display's frame rate.
        while accumulator >= Self.substep - 1e-12 {
            accumulator -= Self.substep
            step(Self.substep)
        }
    }

    private mutating func step(_ h: Double) {
        let distance = root.distance(to: island)
        for index in strands.indices {
            let blueprint = Self.blueprints[index]
            switch strands[index].phase {
            case .attached:
                follow(index, h)
                if distance > configuration.tearDistance * blueprint.tearScale {
                    strands[index].phase = .pinching(elapsed: 0)
                }
            case .pinching(let elapsed):
                follow(index, h)
                let next = elapsed + h
                if next >= Self.pinchDuration {
                    strands[index].phase = .recoiling(elapsed: 0, makeRecoil(index, distance))
                } else {
                    strands[index].phase = .pinching(elapsed: next)
                }
            case .recoiling(let elapsed, var recoil):
                // Underdamped: the stub overshoots into its body, which reads as elastic.
                let omega = 2 * Double.pi * 2.2
                let acceleration = omega * omega * (1 - recoil.progress) - 2 * 0.8 * omega * recoil.speed
                recoil.speed += acceleration * h
                // Once a stub is inside its body it stays there.
                recoil.progress = min(recoil.progress + recoil.speed * h, 1)
                let next = elapsed + h
                strands[index].phase = next >= Self.recoilDuration ? .gone : .recoiling(elapsed: next, recoil)
            case .gone:
                break
            }
        }
    }

    /// Interior nodes chase the rest curve; critically damped, so they lag without jiggling.
    private mutating func follow(_ index: Int, _ h: Double) {
        let targets = restNodes(index)
        for i in 1..<(Self.nodeCount - 1) {
            let u = Double(i) / Double(Self.nodeCount - 1)
            // The middle is the laziest part of the strand.
            let frequency = 9.0 - (9.0 - 4.2) * sin(Double.pi * u)
            let omega = 2 * Double.pi * frequency
            var node = strands[index].nodes[i]
            let toTarget = targets[i].position - node.position
            let acceleration = toTarget * CGFloat(omega * omega) - node.velocity * CGFloat(2 * 1.1 * omega)
            node.velocity = node.velocity + acceleration * CGFloat(h)
            node.position = node.position + node.velocity * CGFloat(h)
            strands[index].nodes[i] = node
        }
        strands[index].nodes[0].position = targets[0].position
        strands[index].nodes[Self.nodeCount - 1].position = targets[Self.nodeCount - 1].position
    }

    private func axes() -> (along: CGPoint, across: CGPoint) {
        let delta = island - root
        let length = delta.length
        let along = length > 0.001 ? delta * (1 / length) : CGPoint(x: 0, y: 1)
        return (along, CGPoint(x: -along.y, y: along.x))
    }

    private func attachments(_ index: Int) -> (root: CGPoint, island: CGPoint) {
        let blueprint = Self.blueprints[index]
        let across = axes().across
        return (
            // Scaled per axis so an attachment never leaves its body, whatever the pull direction.
            root + CGPoint(
                x: across.x * configuration.rootSpread.width, y: across.y * configuration.rootSpread.height)
                * blueprint.offset,
            island + CGPoint(
                x: across.x * configuration.islandSpread.width, y: across.y * configuration.islandSpread.height)
                * blueprint.offset
        )
    }

    /// Where the nodes would sit with no lag: a curve between the attachments that sags
    /// sideways while the strand is short and straightens as it is pulled taut.
    private func restNodes(_ index: Int) -> [Node] {
        let blueprint = Self.blueprints[index]
        let (a, b) = attachments(index)
        let tear = configuration.tearDistance * blueprint.tearScale
        let slack = 22 * max(0, 1 - root.distance(to: island) / tear)
        let control = (a + b) * 0.5 + axes().across * (blueprint.bow * slack)
        return (0..<Self.nodeCount).map { i in
            let u = CGFloat(i) / CGFloat(Self.nodeCount - 1)
            let p = a * ((1 - u) * (1 - u)) + control * (2 * u * (1 - u)) + b * (u * u)
            return Node(position: p)
        }
    }

    private func makeRecoil(_ index: Int, _ distance: CGFloat) -> Recoil {
        let blueprint = Self.blueprints[index]
        let line = centerline(strands[index].nodes.map(\.position))
        let total = line.lengths.last ?? 0
        let breakLength = total * blueprint.neck
        let breakPoint = point(on: line, at: breakLength)
        let (a, b) = attachments(index)
        let endRadius = configuration.endRadius * blueprint.weight
        let neck = Self.neckRadius(
            distance: distance, endRadius: endRadius, tearDistance: configuration.tearDistance * blueprint.tearScale)
        return Recoil(
            rootLength: breakLength,
            islandLength: total - breakLength,
            rootDirection: (breakPoint - a).normalized,
            islandDirection: (breakPoint - b).normalized,
            tipRadius: max(neck * 1.7, 1.6))
    }

    // MARK: Output

    /// The goo to draw for the current state.
    public var frame: SymbioteFrame {
        var frame = SymbioteFrame()
        guard hasInput else { return frame }
        let distance = root.distance(to: island)

        for index in strands.indices {
            let blueprint = Self.blueprints[index]
            let endRadius = configuration.endRadius * blueprint.weight
            let (a, b) = attachments(index)

            switch strands[index].phase {
            case .attached:
                frame.ribbons.append(bridge(index, endRadius: endRadius, distance: distance, pinch: 0))
            case .pinching(let elapsed):
                let pinch = 1 - pow(1 - elapsed / Self.pinchDuration, 0.7)
                frame.ribbons.append(bridge(index, endRadius: endRadius, distance: distance, pinch: CGFloat(pinch)))
            case .recoiling(let elapsed, let recoil):
                let remaining = CGFloat(max(0, 1 - recoil.progress))
                appendStub(
                    to: &frame, from: a, direction: recoil.rootDirection,
                    length: recoil.rootLength * remaining, fullLength: recoil.rootLength,
                    endRadius: endRadius, tipRadius: recoil.tipRadius, elapsed: elapsed, side: 1)
                appendStub(
                    to: &frame, from: b, direction: recoil.islandDirection,
                    length: recoil.islandLength * remaining, fullLength: recoil.islandLength,
                    endRadius: endRadius, tipRadius: recoil.tipRadius, elapsed: elapsed, side: -1)
            case .gone:
                break
            }
        }
        return frame
    }

    /// A strand still joining both bodies: thick where it meets them, thin in between.
    private func bridge(_ index: Int, endRadius: CGFloat, distance: CGFloat, pinch: CGFloat) -> [CGPoint] {
        let blueprint = Self.blueprints[index]
        let line = centerline(strands[index].nodes.map(\.position))
        let total = max(line.lengths.last ?? 0, 0.001)
        let neck = Self.neckRadius(
            distance: distance, endRadius: endRadius, tearDistance: configuration.tearDistance * blueprint.tearScale)
        let flareLength = max(1.7 * endRadius, 9)
        let breakLength = total * blueprint.neck

        let radii = line.lengths.map { s -> CGFloat in
            // Liquid-bridge profile: flares exponentially into both bodies.
            let flare = min(exp(-s / flareLength) + exp(-(total - s) / flareLength), 1)
            var radius = neck + (endRadius - neck) * flare
            // While pinching off, the strand closes to nothing at its break point.
            let fromBreak = (s - breakLength) / 9
            radius *= 1 - pinch * exp(-fromBreak * fromBreak)
            return radius
        }
        return ribbon(line.points, radii)
    }

    /// One half of a torn strand, pulling back into its body with a whip and a bead at its tip.
    private func appendStub(
        to frame: inout SymbioteFrame, from anchor: CGPoint, direction: CGPoint,
        length: CGFloat, fullLength: CGFloat, endRadius: CGFloat, tipRadius: CGFloat,
        elapsed: Double, side: CGFloat
    ) {
        guard length > 0.5, fullLength > 0.5 else { return }
        let across = CGPoint(x: -direction.y, y: direction.x)
        // The stub melts into the body as it gets short.
        let fade = min(1, length / 14)
        let whip = side * 0.3 * length * CGFloat(sin(2 * Double.pi * 6 * elapsed) * exp(-elapsed / 0.22))
        let count = 12
        var points: [CGPoint] = []
        var radii: [CGFloat] = []
        for i in 0..<count {
            let q = CGFloat(i) / CGFloat(count - 1)
            points.append(anchor + direction * (length * q) + across * (whip * q * q))
            let taper = (1 - q) * (1 - q)
            radii.append((tipRadius + (endRadius - tipRadius) * taper) * fade)
        }
        frame.ribbons.append(ribbon(points, radii))
        if let tip = points.last {
            frame.droplets.append(.init(center: tip, radius: tipRadius * 1.25 * fade))
        }
    }

    // MARK: Geometry

    private struct Centerline {
        var points: [CGPoint]
        var lengths: [CGFloat]
    }

    /// A smooth curve through the nodes (Catmull-Rom), with the arc length at each sample.
    private func centerline(_ nodes: [CGPoint]) -> Centerline {
        var points: [CGPoint] = []
        let segments = nodes.count - 1
        for sample in 0..<Self.sampleCount {
            let t = CGFloat(sample) / CGFloat(Self.sampleCount - 1) * CGFloat(segments)
            let segment = min(Int(t), segments - 1)
            let local = t - CGFloat(segment)
            let p0 = nodes[max(segment - 1, 0)]
            let p1 = nodes[segment]
            let p2 = nodes[segment + 1]
            let p3 = nodes[min(segment + 2, segments)]
            let t2 = local * local
            let t3 = t2 * local
            let a = p1 * 2
            let b = (p2 - p0) * local
            let c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
            let d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
            points.append((a + b + c + d) * 0.5)
        }
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + points[i - 1].distance(to: points[i]))
        }
        return Centerline(points: points, lengths: lengths)
    }

    private func point(on line: Centerline, at length: CGFloat) -> CGPoint {
        for i in 1..<line.points.count where line.lengths[i] >= length {
            let span = line.lengths[i] - line.lengths[i - 1]
            let t = span > 0 ? (length - line.lengths[i - 1]) / span : 0
            return line.points[i - 1] + (line.points[i] - line.points[i - 1]) * t
        }
        return line.points.last ?? .zero
    }

    /// The outline of a curve with a radius at every point: one side forward, the other back.
    private func ribbon(_ points: [CGPoint], _ radii: [CGFloat]) -> [CGPoint] {
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in points.indices {
            let before = points[max(i - 1, 0)]
            let after = points[min(i + 1, points.count - 1)]
            let tangent = (after - before).normalized
            let normal = CGPoint(x: -tangent.y, y: tangent.x)
            left.append(points[i] + normal * radii[i])
            right.append(points[i] - normal * radii[i])
        }
        return left + right.reversed()
    }
}

private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var length: CGFloat { (x * x + y * y).squareRoot() }
    var normalized: CGPoint {
        let l = length
        return l > 0.0001 ? self * (1 / l) : CGPoint(x: 0, y: 1)
    }
    func distance(to other: CGPoint) -> CGFloat { (self - other).length }
}
