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

    /// Adds another frame's shapes to this one.
    public mutating func append(_ other: SymbioteFrame) {
        ribbons += other.ribbons
        droplets += other.droplets
        highlights += other.highlights
    }

    /// The smallest rect holding every shape, or nil when there is nothing to draw.
    public var boundingBox: CGRect? {
        var box: CGRect?
        func include(_ rect: CGRect) { box = box?.union(rect) ?? rect }
        for polygon in ribbons {
            for point in polygon { include(CGRect(origin: point, size: .zero)) }
        }
        for droplet in droplets {
            include(CGRect(
                x: droplet.center.x - droplet.radius, y: droplet.center.y - droplet.radius,
                width: droplet.radius * 2, height: droplet.radius * 2))
        }
        return box
    }
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
        /// Set when the root is a flat surface rather than a body: strands take hold of it
        /// along this vector (its length is half the span) however the island is pulled.
        public var rootSpan: CGPoint?

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
    /// A reaching simulation sends its strands out one after another, thinnest first.
    static let reachStagger = 0.014
    /// How long a strand that has just landed takes to spread out on the surface.
    static let contactDuration = 0.14
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
        /// Growing out of the island toward the root; not yet holding it.
        case reaching(elapsed: Double)
        case attached
        case pinching(elapsed: Double)
        case recoiling(elapsed: Double, Recoil)
        case gone
    }

    private struct Strand: Sendable {
        var nodes: [Node] = []
        var phase: Phase = .attached
        /// 0 when the strand has just landed on the root, 1 once it has spread out there.
        var contact: CGFloat = 1
    }

    // MARK: State

    /// The sizes this simulation was created with.
    public let configuration: Configuration
    private var strands: [Strand]
    private var root: CGPoint = .zero
    private var island: CGPoint = .zero
    private var accumulator = 0.0
    private var hasInput = false

    /// Scales every strand's thickness; 1 is the normal look, 0 draws nothing.
    /// Lowered while a landed island soaks its strands back up.
    public var thickness: CGFloat = 1

    /// Creates a simulation with nothing to draw until the first `advance`.
    /// - Parameter reaching: false starts with every strand joining the two bodies (the island
    ///   is about to be pulled off its root); true starts with none, and the strands grow out
    ///   of the island until they take hold of the root.
    public init(configuration: Configuration = Configuration(), reaching: Bool = false) {
        self.configuration = configuration
        strands = Self.blueprints.map { _ in
            Strand(phase: reaching ? .reaching(elapsed: 0) : .attached)
        }
    }

    /// True from the step on which the main strand starts to break (or is called back before
    /// it ever took hold).
    public var isTorn: Bool {
        switch strands[0].phase {
        case .reaching, .attached: return false
        case .pinching, .recoiling, .gone: return true
        }
    }

    /// True while the main strand joins the island to the root.
    public var isHolding: Bool {
        if case .attached = strands[0].phase { return true }
        return false
    }

    /// Breaks every strand that is still attached, right now. The drag controller calls this
    /// when `IslandState.drag(to:)` returns true, so the state and the effect cannot disagree
    /// about whether the island has torn. Strands still reaching are called back; strands
    /// already breaking or gone are left alone.
    public mutating func tear() {
        for index in strands.indices {
            switch strands[index].phase {
            case .attached:
                strands[index].phase = .pinching(elapsed: 0)
            case .reaching(let elapsed):
                strands[index].phase = retraction(index, elapsed)
            case .pinching, .recoiling, .gone:
                break
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
            case .reaching(let elapsed):
                follow(index, h)
                let next = elapsed + h
                if distance > configuration.tearDistance * blueprint.tearScale {
                    // Out of range before it landed: the feeler is drawn back in.
                    strands[index].phase = retraction(index, elapsed)
                } else if Self.reachProgress(index, next) >= 1 {
                    strands[index].phase = .attached
                    strands[index].contact = 0
                } else {
                    strands[index].phase = .reaching(elapsed: next)
                }
            case .attached:
                follow(index, h)
                strands[index].contact = min(
                    strands[index].contact + CGFloat(h / Self.contactDuration), 1)
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
        // A flat surface is held along itself; a body is held across the pull, scaled per
        // axis so an attachment never leaves the body, whatever the pull direction.
        let rootSpan = configuration.rootSpan ?? CGPoint(
            x: across.x * configuration.rootSpread.width, y: across.y * configuration.rootSpread.height)
        return (
            root + rootSpan * blueprint.offset,
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

    /// How far a reaching strand has grown, 0...1. Thin strands set off first and are quick;
    /// the trunk follows, so the island is seen to feel for the surface before it grabs it.
    static func reachProgress(_ index: Int, _ elapsed: Double) -> Double {
        let delay = Double(blueprints.count - 1 - index) * reachStagger
        let duration = 0.11 + 0.09 * Double(blueprints[index].weight)
        let t = min(max((elapsed - delay) / duration, 0), 1)
        // Shoots out and slows as it arrives.
        return 1 - (1 - t) * (1 - t) * (1 - t)
    }

    /// The feeler of a strand that never landed, drawn back into the island.
    private func retraction(_ index: Int, _ elapsed: Double) -> Phase {
        let progress = CGFloat(Self.reachProgress(index, elapsed))
        let line = centerline(strands[index].nodes.map(\.position))
        let total = line.lengths.last ?? 0
        let length = total * progress
        guard length > 0.5 else { return .gone }
        let (_, b) = attachments(index)
        let tip = point(on: line, at: total - length)
        let endRadius = configuration.endRadius * Self.blueprints[index].weight
        return .recoiling(elapsed: 0, Recoil(
            rootLength: 0, islandLength: length, rootDirection: CGPoint(x: 0, y: 1),
            islandDirection: (tip - b).normalized, tipRadius: max(0.35 * endRadius, 1.2)))
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
            case .reaching(let elapsed):
                appendFeeler(
                    to: &frame, index, endRadius: endRadius, distance: distance,
                    progress: CGFloat(Self.reachProgress(index, elapsed)))
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

        // A strand that has just landed spreads out on the root, a little too far at first.
        let contact = strands[index].contact
        let splat = contact + 1.6 * sin(.pi * contact) * (1 - contact)
        let radii = line.lengths.map { s -> CGFloat in
            // Liquid-bridge profile: flares exponentially into both bodies.
            let flare = min(
                exp(-s / flareLength) * splat + exp(-(total - s) / flareLength), max(splat, 1))
            var radius = neck + (endRadius - neck) * flare
            // Thicker strands are slightly lumpy, like something organic rather than a drawn line.
            if endRadius >= Self.texturedRadius {
                radius *= 1 + 0.16 * sin(s / (0.8 * endRadius) + CGFloat(index) * 1.7)
            }
            // While pinching off, the strand closes to nothing at its break point.
            let fromBreak = (s - breakLength) / 9
            radius *= 1 - pinch * exp(-fromBreak * fromBreak)
            // With the bodies together there is no gap to bridge; without this the flares
            // would poke out of a resting island as bumps.
            radius *= smoothstep(0, 24, distance)
            return radius * thickness
        }
        frame.ribbons.append(ribbon(line.points, radii, firstNormal: surfaceTangent))
        appendFoot(to: &frame, at: line.points[0], radius: radii[0])
        if endRadius >= Self.texturedRadius {
            if let sheen = highlight(line.points, radii) { frame.highlights.append(sheen) }
            if let rim = rimLight(line.points, radii) { frame.highlights.append(rim) }
        }
    }

    /// A strand on its way out of the island: thick where it leaves, a thin tip with a bead.
    private func appendFeeler(
        to frame: inout SymbioteFrame, _ index: Int, endRadius: CGFloat, distance: CGFloat,
        progress: CGFloat
    ) {
        let blueprint = Self.blueprints[index]
        let line = centerline(strands[index].nodes.map(\.position))
        let total = max(line.lengths.last ?? 0, 0.001)
        // The strand runs root to island; the feeler is its island end.
        let start = total * (1 - progress)
        guard total - start > 0.5 else { return }
        let neck = Self.neckRadius(
            distance: distance, endRadius: endRadius, tearDistance: configuration.tearDistance * blueprint.tearScale)
        let flareLength = max(1.7 * endRadius, 9)
        let tipRadius = max(0.6 * neck, 0.8)
        let scale = smoothstep(0, 24, distance) * thickness

        var points = [point(on: line, at: start)]
        var lengths = [start]
        for i in line.points.indices where line.lengths[i] > start + 0.5 {
            points.append(line.points[i])
            lengths.append(line.lengths[i])
        }
        guard points.count >= 2 else { return }
        let radii = lengths.map { s -> CGFloat in
            let body = neck + (endRadius - neck) * min(exp(-(total - s) / flareLength), 1)
            return (tipRadius + (body - tipRadius) * smoothstep(0, 16, s - start)) * scale
        }
        frame.ribbons.append(ribbon(points, radii))
        if endRadius >= Self.texturedRadius, let sheen = highlight(points, radii) {
            frame.highlights.append(sheen)
        }
        let bead = max(1.5 * neck, 1.5) * scale
        if bead > 0.3 { frame.droplets.append(.init(center: points[0], radius: bead)) }
    }

    /// One half of a torn strand, pulling back into its body with a whip and a bead at its tip.
    private func appendStub(
        to frame: inout SymbioteFrame, from anchor: CGPoint, direction: CGPoint,
        length: CGFloat, fullLength: CGFloat, endRadius: CGFloat, tipRadius: CGFloat,
        elapsed: Double, side: CGFloat
    ) {
        guard length > 0.5, fullLength > 0.5 else { return }
        // `side` 1 is the half left on the root.
        let onSurface = side > 0 && configuration.rootSpan != nil
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
            radii.append((tipRadius + (endRadius - tipRadius) * taper) * fade * thickness)
        }
        frame.ribbons.append(ribbon(points, radii, firstNormal: onSurface ? surfaceTangent : nil))
        if onSurface { appendFoot(to: &frame, at: anchor, radius: radii[0]) }
        if endRadius >= Self.texturedRadius, let sheen = highlight(points, radii) {
            frame.highlights.append(sheen)
        }
        if let tip = points.last {
            let radius = tipRadius * 1.25 * fade * thickness
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

    /// Unit vector along the surface the root is, or nil when the root is a body.
    private var surfaceTangent: CGPoint? {
        configuration.rootSpan.map(\.normalized)
    }

    /// Where a strand holds a flat surface it spreads into a low mound lying on it.
    private func appendFoot(to frame: inout SymbioteFrame, at point: CGPoint, radius: CGFloat) {
        guard let tangent = surfaceTangent, radius > 0.4 else { return }
        // The mound rises on the island's side of the surface.
        var up = CGPoint(x: -tangent.y, y: tangent.x)
        let toIsland = island - root
        if up.x * toIsland.x + up.y * toIsland.y < 0 { up = up * -1 }
        let halfWidth = 1.7 * radius
        let height = 0.6 * radius
        var polygon: [CGPoint] = []
        let steps = 10
        for step in 0...steps {
            let angle = CGFloat.pi * CGFloat(step) / CGFloat(steps)
            polygon.append(point + tangent * (halfWidth * cos(angle)) + up * (height * sin(angle)))
        }
        // Ribbons all wind the same way; a shape wound the other way would punch a hole in
        // them under the nonzero fill rule.
        if signedArea(polygon) > 0 { polygon.reverse() }
        frame.ribbons.append(polygon)
    }

    /// Shoelace area; ribbons built by `ribbon` are negative.
    private func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
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
    /// - Parameter firstNormal: when set, the first end is cut along this unit vector instead
    ///   of square to the curve, so a strand that meets a surface ends flat on it.
    private func ribbon(
        _ points: [CGPoint], _ radii: [CGFloat], firstNormal: CGPoint? = nil
    ) -> [CGPoint] {
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in points.indices {
            let before = points[max(i - 1, 0)]
            let after = points[min(i + 1, points.count - 1)]
            let tangent = (after - before).normalized
            var normal = CGPoint(x: -tangent.y, y: tangent.x)
            if i == 0, let firstNormal {
                // Keep the side the outline is already on.
                let sameSide = normal.x * firstNormal.x + normal.y * firstNormal.y >= 0
                normal = sameSide ? firstNormal : firstNormal * -1
            }
            left.append(points[i] + normal * radii[i])
            right.append(points[i] - normal * radii[i])
        }
        var outline = left + right.reversed()
        if let firstNormal, let base = points.first, let end = points.last {
            // A strand that leaves the surface at a slant would bulge through it just past
            // its base; whatever crosses the surface is laid back onto it.
            var up = CGPoint(x: -firstNormal.y, y: firstNormal.x)
            if up.x * (end.x - base.x) + up.y * (end.y - base.y) < 0 { up = up * -1 }
            for i in outline.indices {
                let height = (outline[i].x - base.x) * up.x + (outline[i].y - base.y) * up.y
                if height < 0 { outline[i] = outline[i] - up * height }
            }
        }
        return outline
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
