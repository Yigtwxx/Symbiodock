import CoreGraphics
import Foundation

/// What the renderer draws for one instant: goo shapes only, never the island or the root.
public struct SymbioteFrame: Equatable, Sendable {
    /// A bead of goo drawn as a filled circle, such as the tip of a snapped-back stub.
    public struct Droplet: Equatable, Sendable {
        public var center: CGPoint
        public var radius: CGFloat

        public init(center: CGPoint, radius: CGFloat) {
            self.center = center
            self.radius = radius
        }
    }

    /// Closed polygons, one per strand or stub.
    public var ribbons: [[CGPoint]]
    /// Beads at the tips of torn stubs.
    public var droplets: [Droplet]

    /// Thin closed polygons along the lit side of the thicker strands: a wet sheen.
    public var highlights: [[CGPoint]]

    public init(
        ribbons: [[CGPoint]] = [], droplets: [Droplet] = [], highlights: [[CGPoint]] = []
    ) {
        self.highlights = highlights
        self.ribbons = ribbons
        self.droplets = droplets
    }

    /// True when there is nothing to draw.
    public var isEmpty: Bool { ribbons.isEmpty && droplets.isEmpty }
}

/// Sticky strands between the place the island was attached (the root) and the island.
///
/// Pure and deterministic: the same sequence of `advance` calls always gives the same frames.
/// Strands lag behind the pointer like syrup, thin out as they stretch, pinch off past their
/// tear distance (thin ones first), and the two halves snap back into their bodies.
public struct SymbioteSimulation: Sendable {
    /// Sizes of the effect; the defaults are the approved look.
    public struct Configuration: Equatable, Sendable {
        /// Distance at which the main strand tears; shares its default with `IslandState`.
        public var tearDistance: CGFloat = IslandDrag.tearDistance
        /// Half the size of the area inside the root body over which strands attach.
        public var rootSpread = CGSize(width: 62, height: 7)
        /// Half the size of the area inside the island body over which strands attach.
        public var islandSpread = CGSize(width: 70, height: 9)
        /// Radius of the main strand where it meets a body.
        public var endRadius: CGFloat = 15

        /// The default configuration.
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
    /// Strands at least this thick where they meet a body get lumps and a sheen.
    static let texturedRadius: CGFloat = 4
    /// Where the light comes from, for the sheen: up and to the left.
    static let lightDirection = CGPoint(x: -0.6, y: -0.8)

    private struct Blueprint {
        var weight: CGFloat      // thickness relative to the main strand
        var offset: CGFloat      // attachment position across the bodies, -1...1
        var tearScale: CGFloat   // fraction of the tear distance at which this strand goes
        var neck: CGFloat        // where along the strand it breaks, 0...1
        var bow: CGFloat         // slack sideways sag while short
    }

    private static let blueprints: [Blueprint] = [
        // Thick trunks, medium cords and hair-thin threads, mixed across the bodies.
        Blueprint(weight: 1.00, offset: 0.05, tearScale: 1.00, neck: 0.50, bow: 0.15),
        Blueprint(weight: 0.78, offset: -0.46, tearScale: 0.95, neck: 0.44, bow: -1.0),
        Blueprint(weight: 0.62, offset: 0.56, tearScale: 0.90, neck: 0.57, bow: 1.0),
        Blueprint(weight: 0.46, offset: -0.78, tearScale: 0.85, neck: 0.50, bow: -1.3),
        Blueprint(weight: 0.38, offset: 0.28, tearScale: 0.83, neck: 0.53, bow: 0.6),
        Blueprint(weight: 0.28, offset: -0.22, tearScale: 0.79, neck: 0.47, bow: -0.5),
        Blueprint(weight: 0.22, offset: 0.82, tearScale: 0.76, neck: 0.45, bow: 1.4),
        Blueprint(weight: 0.17, offset: -0.62, tearScale: 0.73, neck: 0.55, bow: -0.9),
        Blueprint(weight: 0.13, offset: 0.42, tearScale: 0.70, neck: 0.49, bow: 0.8),
        Blueprint(weight: 0.10, offset: -0.06, tearScale: 0.67, neck: 0.52, bow: 0.3),
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

    /// The sizes this simulation was created with.
    public let configuration: Configuration
    private var strands: [Strand]
    private var root: CGPoint = .zero
    private var island: CGPoint = .zero
    private var accumulator = 0.0
    private var hasInput = false

    /// Creates a simulation with nothing to draw until the first `advance`.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        strands = Self.blueprints.map { _ in Strand() }
    }

    /// True from the step on which the main strand starts to break.
    public var isTorn: Bool {
        if case .attached = strands[0].phase { return false }
        return true
    }

    /// Breaks every strand that is still attached, right now. The drag controller calls this
    /// when `IslandState.drag(to:)` returns true, so the state and the effect cannot disagree
    /// about whether the island has torn. Strands already breaking or gone are left alone.
    public mutating func tear() {
        for index in strands.indices {
            if case .attached = strands[index].phase {
                strands[index].phase = .pinching(elapsed: 0)
            }
        }
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
        // Hair-thin strands may go below the usual floor, or they would all look alike.
        return max(conserved * late, min(minimumNeckRadius, 0.45 * endRadius))
    }

    // MARK: Stepping

    /// Moves the simulation forward by `dt` seconds with the bodies at the given points.
    /// Non-finite input is ignored, so one bad sample cannot poison the state for good.
    public mutating func advance(root: CGPoint, island: CGPoint, dt: Double) {
        guard dt.isFinite, root.x.isFinite, root.y.isFinite, island.x.isFinite, island.y.isFinite
        else { return }
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
                // Gone once the stub is back in its body; the duration is only an upper bound.
                let done = recoil.progress >= 1 || next >= Self.recoilDuration
                strands[index].phase = done ? .gone : .recoiling(elapsed: next, recoil)
            case .gone:
                break
            }
        }
    }

    /// Interior nodes chase the rest curve; slightly overdamped (ratio 1.1), so they lag without jiggling.
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
                appendBridge(to: &frame, index, endRadius: endRadius, distance: distance, pinch: 0)
            case .pinching(let elapsed):
                let pinch = 1 - pow(1 - elapsed / Self.pinchDuration, 0.7)
                appendBridge(to: &frame, index, endRadius: endRadius, distance: distance, pinch: CGFloat(pinch))
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
    private func appendBridge(
        to frame: inout SymbioteFrame, _ index: Int, endRadius: CGFloat, distance: CGFloat, pinch: CGFloat
    ) {
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
            // Thicker strands are slightly lumpy, like something organic rather than a drawn line.
            if endRadius >= Self.texturedRadius {
                radius *= 1 + 0.16 * sin(s / (0.8 * endRadius) + CGFloat(index) * 1.7)
            }
            // While pinching off, the strand closes to nothing at its break point.
            let fromBreak = (s - breakLength) / 9
            radius *= 1 - pinch * exp(-fromBreak * fromBreak)
            return radius
        }
        frame.ribbons.append(ribbon(line.points, radii))
        if endRadius >= Self.texturedRadius {
            if let sheen = highlight(line.points, radii) { frame.highlights.append(sheen) }
            if let rim = rimLight(line.points, radii) { frame.highlights.append(rim) }
        }
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
        if endRadius >= Self.texturedRadius, let sheen = highlight(points, radii) {
            frame.highlights.append(sheen)
        }
        if let tip = points.last {
            let radius = tipRadius * 1.25 * fade
            frame.droplets.append(.init(center: tip, radius: radius))
            if radius >= 2 {
                // A glint on the bead, on the lit side.
                let center = tip + Self.lightDirection * (radius * 0.38)
                frame.highlights.append((0..<8).map { step in
                    let angle = CGFloat(step) / 8 * 2 * .pi
                    return center + CGPoint(x: cos(angle), y: sin(angle)) * (radius * 0.26)
                })
            }
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

    /// A thin sliver along the lit side of a strand, fading out toward both ends.
    private func highlight(_ points: [CGPoint], _ radii: [CGFloat]) -> [CGPoint]? {
        sliver(points, radii, side: 1, inset: 0.42, width: 0.2)
    }

    /// A fainter line along the far side, which makes the strand read as round.
    private func rimLight(_ points: [CGPoint], _ radii: [CGFloat]) -> [CGPoint]? {
        sliver(points, radii, side: -1, inset: 0.62, width: 0.07)
    }

    private func sliver(
        _ points: [CGPoint], _ radii: [CGFloat], side: CGFloat, inset: CGFloat, width: CGFloat
    ) -> [CGPoint]? {
        let skip = points.count / 6
        let range = skip..<(points.count - skip)
        guard range.count >= 3 else { return nil }
        var shifted: [CGPoint] = []
        var widths: [CGFloat] = []
        for i in range {
            let tangent = (points[min(i + 1, points.count - 1)] - points[max(i - 1, 0)]).normalized
            var normal = CGPoint(x: -tangent.y, y: tangent.x)
            if normal.x * Self.lightDirection.x + normal.y * Self.lightDirection.y < 0 {
                normal = normal * -1
            }
            normal = normal * side
            let t = CGFloat(i - range.lowerBound) / CGFloat(range.count - 1)
            shifted.append(points[i] + normal * (radii[i] * inset))
            widths.append(max(radii[i] * width * sin(CGFloat.pi * t), 0.12))
        }
        return ribbon(shifted, widths)
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
