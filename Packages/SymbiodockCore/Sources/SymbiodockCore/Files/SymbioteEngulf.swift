import CoreGraphics
import Foundation

/// The goo that swallows a file tile while it converts: a pure function of the phase, so any
/// frame can be drawn on its own.
///
/// Closing, feelers with thin, beaded tips creep in from all round the edge, as the drag
/// effect's island feels for a surface; their roots swell, they thicken into ropes, a core
/// gathers in the middle where they meet, and the gaps between them narrow to lenses and
/// close. Opening, the cover parts as the drag effect's two bodies do: it tears down the
/// middle and the tear widens to the sides, ropes stretched across it thin out and snap, and
/// their halves pull back to the edges as beaded stubs.
///
/// Drawn by the drag effect's canvas (blur 5, alpha threshold 0.5, then the crisp shapes), so
/// shapes closer than about 10 pt web together and anything thinner than about 1.3 pt shows
/// only in the crisp layer; no strand is drawn thinner than that away from its tip. Coverage
/// only grows while closing and only shrinks while opening, give or take a moving bead.
public enum SymbioteEngulf {
    /// How far goo may bulge past the tile; the canvas is this much larger on every side.
    public static let overhang: CGFloat = 10
    /// The strands that reach in, three from each side.
    public static let strandCount = 12

    // MARK: Tuning: everywhere

    /// Goo is cut this far outside the tile: half the 8 pt gap to the next tile, so it never
    /// darkens a neighbour. The canvas's larger overhang leaves the blur room around it.
    static let margin: CGFloat = 4
    /// Strands start this far outside the edge they root on, so they enter the tile already round.
    static let rootOutset: CGFloat = 4
    /// Points along each strand's curve.
    static let sampleCount = 32
    /// The thinnest a strand gets away from its tip: thinner, the blur would swallow it.
    static let minimumRadius: CGFloat = 1.3
    /// A torn stub melts into its edge once it is shorter than this.
    static let meltLength: CGFloat = 14
    /// A strand's tip is this share of its neck, and never thinner than `tipFloor`: tips stay
    /// thin while roots thicken. A feeler narrows into it all along its length, as a tentacle
    /// does: the larger the power, the sooner it thins.
    static let tipShare: CGFloat = 0.4
    static let tipFloor: CGFloat = 1.1
    static let taperPower: CGFloat = 0.55
    /// The bead balled up on a feeler's tip or a torn end, relative to the tip; a bead that
    /// melts below `minimumBead` is gone.
    static let beadShare: CGFloat = 1.6
    static let minimumBead: CGFloat = 0.4
    /// Lumps along a strand: this deep, one every `lumpSpacing` × 2π pt, shifted by
    /// `lumpPhase` from one strand to the next so that no two swell in step.
    static let lumpDepth: CGFloat = 0.1
    static let lumpSpacing: CGFloat = 5
    static let lumpPhase: CGFloat = 1.7
    /// Strands at least this heavy carry a sheen, along the part of them at least this thick:
    /// as in the drag effect, only the thick goo near a body shines.
    static let sheenWeight: CGFloat = 0.85
    static let sheenThickness: CGFloat = 3
    /// A sheen follows the rope, never more than this many necks wide, not the root's steep
    /// swelling, which would fold the sliver into a chevron.
    static let sheenNecks: CGFloat = 2.5

    // MARK: Tuning: closing

    /// Every strand takes this share of the progress to reach as far as it goes, after its delay.
    static let reachSpan = 0.42
    /// Root radius while the strands creep in; it swells to `rootShare` of the shorter side
    /// from `rootSwell` of the progress on.
    static let rootStart: CGFloat = 3
    static let rootShare: CGFloat = 0.4
    static let rootSwell: CGFloat = 0.15
    /// Radius of the thin part of a strand, before and after it thickens.
    static let neckStart: CGFloat = 1.6
    static let neckEnd: CGFloat = 5.2
    /// How far into the tile a root's swelling reaches, as a share of the shorter side: the
    /// roots hold the edges and the necks the middle, so the gaps close as lenses.
    static let flareShare: CGFloat = 0.2
    /// A strand bows sideways by `bowShare` of its length: `bowLead` times that a third of the
    /// way along, then back the other way by `bowReturn` times it at two thirds, an S rather
    /// than an arc. It heads `aimShare` of the shorter side to one side of the middle, so the
    /// strands curve past one another rather than form a star.
    static let bowShare: CGFloat = 0.22
    static let bowLead: CGFloat = 1.3
    static let bowReturn: CGFloat = 0.45
    static let aimShare: CGFloat = 0.2
    /// A strand heads for a point past the middle by this share of the way it came, plus as
    /// much again times its weight, and reaches `depth` of the way there: heavy ropes reach
    /// furthest, light feelers stop short.
    static let pastCore: CGFloat = 0.05
    static let pastCorePerWeight: CGFloat = 0.08
    /// The core gathers where the feelers meet, from this progress on, and grows to this share
    /// of each side: wide enough to close the middle of each edge, between the roots, before
    /// the cover rectangle comes in.
    static let coreStart: CGFloat = 0.45
    static let coreShare: CGFloat = 0.56
    /// Points round the core's outline, and its lumps: each `(depth, waves, phase)` adds
    /// `depth · sin(waves · angle + phase)` to its radius.
    static let coreSamples = 40
    static let coreLumps: [(depth: CGFloat, waves: CGFloat, phase: CGFloat)] = [
        (0.07, 3, 0.6), (0.04, 5, 2.1),
    ]
    /// The ropes' sheens fade over this stretch of the progress, before the ropes merge into
    /// one black mass, where a sheen would read as a scratch.
    static let sheenFadeStart: CGFloat = 0.35
    static let sheenFadeEnd: CGFloat = 0.55
    /// The cocoon's glints come in over the last stretch of the closing.
    static let glintsStart: CGFloat = 0.8
    /// How far the cover rectangle reaches past the tile once it is closed.
    static let coverOutset: CGFloat = 2

    // MARK: Tuning: opening

    /// Where the cover tears open, in shares of the tile's sides.
    static let tearCentre = CGPoint(x: 0.5, y: 0.42)
    /// The cover splits as the drag effect's two bodies part: the tear runs up and down the
    /// tile first, by `runEnd` of the opening, and widens to the sides by `holeEnd`, with ropes
    /// stretched across it from side to side. Both go fast at first, as a tear, then slow.
    static let runEnd: CGFloat = 0.45
    static let holeEnd: CGFloat = 0.97
    static let holeEase: CGFloat = 1.6
    /// The hole's half-axes at the end, in halves of the tile's sides; past √2 plus the lumps,
    /// so the corners open too.
    static let holeReach: CGFloat = 1.8
    /// Rays round the hole's outline, and its lumps, as the core's: deep and few, so the tear
    /// is ragged and lopsided rather than an oval.
    static let holeSamples = 60
    static let holeLumps: [(depth: CGFloat, waves: CGFloat, phase: CGFloat)] = [
        (0.13, 3, 0.9), (0.08, 5, 2.6), (0.05, 8, 1.2),
    ]
    /// A rope across the hole: its neck in the closed cover and where it swells into the
    /// cover, before its weight, and the share of that neck it thins to before it snaps.
    static let ropeNeck: CGFloat = 3
    static let ropeRoot: CGFloat = 10
    static let stretchedNeck: CGFloat = 0.35
    /// Share of the opening a rope takes to pinch through once it starts to snap, and the ease
    /// of the pinch: the drag effect's, quick to start.
    static let pinchSpan: CGFloat = 0.06
    static let pinchEase: CGFloat = 0.7
    /// Half width of the pinch along a rope, as in the drag effect's tear.
    static let pinchWidth: CGFloat = 7
    /// Share of the opening the halves of a snapped rope take to pull back to the edge.
    static let recoilSpan: CGFloat = 0.4
    /// The cocoon's glints fade over the first stretch of the opening.
    static let glintsEnd: CGFloat = 0.2

    private enum Side { case top, right, bottom, left }

    /// One strand that reaches in while the tile closes.
    private struct Blueprint {
        var side: Side
        var along: CGFloat   // where on that side, 0...1, running clockwise round the tile
        var delay: Double    // share of the progress before it sets off, 0...0.28
        var bow: CGFloat     // sideways sag, -1...1
        var aim: CGFloat     // how far to one side of the middle it heads, -1...1
        var weight: CGFloat  // thickness relative to the heaviest strand
        var depth: CGFloat   // how far toward that point it reaches, 0...1
    }

    private static let blueprints: [Blueprint] = [
        // Three per side, a little off even spacing. Light feelers set off first; one heavy
        // trunk per side follows, as the drag effect's island feels before it grabs. The trunks
        // sit at different places on their sides, so their sheens never line up into a cross.
        Blueprint(side: .top, along: 0.14, delay: 0.20, bow: 0.6, aim: 0.7, weight: 1.00, depth: 0.8),
        Blueprint(side: .top, along: 0.52, delay: 0.05, bow: -0.4, aim: -0.5, weight: 0.62, depth: 0.5),
        Blueprint(side: .top, along: 0.86, delay: 0.00, bow: -0.9, aim: 0.2, weight: 0.70, depth: 0.62),
        Blueprint(side: .right, along: 0.16, delay: 0.12, bow: 0.8, aim: -0.8, weight: 0.66, depth: 0.55),
        Blueprint(side: .right, along: 0.49, delay: 0.03, bow: -0.3, aim: 0.6, weight: 0.72, depth: 0.7),
        Blueprint(side: .right, along: 0.83, delay: 0.26, bow: 0.7, aim: 0.1, weight: 0.94, depth: 0.75),
        Blueprint(side: .bottom, along: 0.12, delay: 0.17, bow: -0.7, aim: 0.5, weight: 0.60, depth: 0.45),
        Blueprint(side: .bottom, along: 0.47, delay: 0.28, bow: 0.5, aim: -0.7, weight: 0.98, depth: 0.85),
        Blueprint(side: .bottom, along: 0.85, delay: 0.08, bow: -0.5, aim: 0.9, weight: 0.68, depth: 0.55),
        Blueprint(side: .left, along: 0.18, delay: 0.10, bow: 0.9, aim: -0.4, weight: 0.76, depth: 0.5),
        Blueprint(side: .left, along: 0.53, delay: 0.02, bow: -0.6, aim: 0.8, weight: 0.76, depth: 0.68),
        Blueprint(side: .left, along: 0.87, delay: 0.23, bow: 0.4, aim: -0.6, weight: 0.90, depth: 0.78),
    ]

    /// One rope left stretched across the hole while the tile opens.
    private struct Bridge {
        var from: (side: Side, along: CGFloat)
        var to: (side: Side, along: CGFloat)
        var bow: CGFloat     // sideways sag, -1...1
        var weight: CGFloat  // thickness relative to the heaviest strand
        var snap: CGFloat    // share of the opening at which it starts to pinch
        var tear: CGFloat    // where along it it pinches, 0...1
    }

    private static let bridges: [Bridge] = [
        // From side to side across the tear, a little off even spacing and slant, so their gaps
        // are lenses of different sizes. The thin ones snap first, as in the drag effect.
        Bridge(from: (.left, 0.86), to: (.right, 0.26), bow: 0.5, weight: 0.55, snap: 0.2, tear: 0.45),
        Bridge(from: (.left, 0.70), to: (.right, 0.24), bow: -0.35, weight: 0.9, snap: 0.44, tear: 0.55),
        Bridge(from: (.left, 0.55), to: (.right, 0.40), bow: 0.45, weight: 0.6, snap: 0.27, tear: 0.5),
        Bridge(from: (.left, 0.48), to: (.right, 0.64), bow: -0.3, weight: 1.0, snap: 0.52, tear: 0.45),
        Bridge(from: (.left, 0.28), to: (.right, 0.66), bow: 0.5, weight: 0.5, snap: 0.32, tear: 0.55),
        Bridge(from: (.left, 0.14), to: (.right, 0.80), bow: -0.4, weight: 0.8, snap: 0.4, tear: 0.5),
    ]

    /// One strand's fixed path across a tile.
    private struct Strand {
        var line: SymbioteGeometry.Centerline
        var total: CGFloat
        /// Arc length over which a root's swelling falls off.
        var flare: CGFloat
        /// The side of the strand the light falls on, kept all along it.
        var lit: CGPoint
    }

    // MARK: Frames

    /// The goo over a tile occupying (0, 0, size), in the tile's own coordinates.
    public static func frame(size: CGSize, phase: EngulfPhase) -> SymbioteFrame {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite
        else { return SymbioteFrame() }
        switch phase {
        case .engulf(let progress):
            // `!(x > 0)` also turns a NaN away.
            guard progress > 0 else { return SymbioteFrame() }
            return progress >= 1 ? cocoon(size) : engulf(size, CGFloat(progress))
        case .cocoon:
            return cocoon(size)
        case .reveal(let progress):
            if progress <= 0 { return cocoon(size) }
            guard progress < 1 else { return SymbioteFrame() }
            return reveal(size, CGFloat(progress))
        case .done:
            return SymbioteFrame()
        }
    }

    /// Strands reaching in and thickening; the cocoon's glints fade in at the very end.
    private static func engulf(_ size: CGSize, _ progress: CGFloat) -> SymbioteFrame {
        var frame = goo(size, progress)
        frame.highlights += glints(size, scale: smoothstep(glintsStart, 1, progress))
        return clipped(frame, size)
    }

    /// The closed cover: the strands at full thickness, the core, and the tile's rectangle
    /// under them, so full cover is a fact rather than a hope.
    private static func cocoon(_ size: CGSize) -> SymbioteFrame {
        var frame = goo(size, 1)
        frame.ribbons.append(wound(rectangle(CGRect(origin: .zero, size: size)
            .insetBy(dx: -coverOutset, dy: -coverOutset))))
        frame.highlights += glints(size, scale: 1)
        return clipped(frame, size)
    }

    /// The strands and the core at closing progress `progress`.
    private static func goo(_ size: CGSize, _ progress: CGFloat) -> SymbioteFrame {
        var frame = SymbioteFrame()
        let shorter = min(size.width, size.height)
        let swell = smoothstep(rootSwell, 1, progress)
        let thicken = smoothstep(0, 1, progress)
        // The ropes' sheen gives way to the cocoon's own glints as the strands merge.
        let shine = 1 - smoothstep(sheenFadeStart, sheenFadeEnd, progress)
        for (index, blueprint) in blueprints.enumerated() {
            let reach = reachProgress(blueprint, progress)
            guard reach > 0 else { continue }
            let strand = strand(blueprint, size)
            let neck = max(minimumRadius, blueprint.weight * lerp(neckStart, neckEnd, thicken))
            let root = blueprint.weight * lerp(rootStart, rootShare * shorter, swell)
            let length = strand.total * reach
            let (points, lengths) = prefix(of: strand.line, upTo: length)
            guard points.count >= 2 else { continue }
            let radii = lengths.map { s in
                tapered(
                    body(s, flare: strand.flare, root: root, neck: neck, index: index),
                    neck: neck, at: s, of: length)
            }
            frame.ribbons.append(rooted(points, radii))
            // A bead at the tip, as on the drag effect's feelers.
            frame.droplets.append(.init(center: points[points.count - 1], radius: beadShare * tipRadius(neck)))
            if blueprint.weight >= sheenWeight, shine > 0.05,
                let thick = radii.lastIndex(where: { $0 >= sheenThickness }), thick >= 5,
                let sheen = SymbioteGeometry.sheen(
                    Array(points[...thick]), radii[...thick].map { min($0, sheenNecks * neck) },
                    minimumWidth: 0.12, widthScale: shine, facing: strand.lit)
            {
                frame.highlights.append(sheen)
            }
        }
        let gather = smoothstep(coreStart, 1, progress)
        if gather > 0 { frame.ribbons.append(core(size, scale: gather)) }
        return frame
    }

    /// The cover torn open from the middle: a hole that spreads to the edges, ropes stretched
    /// across it that thin and snap, and their halves pulling back to the edge.
    private static func reveal(_ size: CGSize, _ progress: CGFloat) -> SymbioteFrame {
        var frame = SymbioteFrame()
        frame.ribbons += cover(size, hole: hole(progress))
        for (index, bridge) in bridges.enumerated() {
            frame.append(rope(bridge, index: index, size: size, progress: progress))
        }
        frame.highlights += glints(size, scale: 1 - smoothstep(0, glintsEnd, progress))
        return clipped(frame, size)
    }

    // MARK: Strands

    /// How far a strand has reached in, 0...1: it shoots in and slows as it lands.
    private static func reachProgress(_ blueprint: Blueprint, _ progress: CGFloat) -> CGFloat {
        let t = min(max((Double(progress) - blueprint.delay) / reachSpan, 0), 1)
        return CGFloat(1 - pow(1 - t, 3))
    }

    /// The thickness a strand would have at `s` with nothing tapering it: its root swells into
    /// the tile near the edge, the rest stays near the neck, and it is slightly lumpy, like
    /// something organic rather than a drawn line.
    private static func body(
        _ s: CGFloat, flare: CGFloat, root: CGFloat, neck: CGFloat, index: Int
    ) -> CGFloat {
        neck + max(root - neck, 0) * exp(-s / flare) * lump(s, index)
    }

    /// `body` at `s` along a feeler `length` long, narrowing all the way into its tip. A point
    /// of the feeler only ever gets thicker as the feeler grows and thickens.
    private static func tapered(_ body: CGFloat, neck: CGFloat, at s: CGFloat, of length: CGFloat) -> CGFloat {
        let tip = tipRadius(neck)
        return tip + (body - tip) * pow(max(1 - s / length, 0), taperPower)
    }

    /// The tip of a strand whose neck is `neck`.
    private static func tipRadius(_ neck: CGFloat) -> CGFloat {
        max(tipFloor, tipShare * neck)
    }

    /// Fixed along the strand, so the lumps swell with it rather than slide.
    private static func lump(_ s: CGFloat, _ index: Int) -> CGFloat {
        1 + lumpDepth * sin(s / lumpSpacing + CGFloat(index) * lumpPhase)
    }

    /// Where a point `along` a side lies, and the way out of the tile there.
    private static func edgePoint(
        _ side: Side, _ along: CGFloat, _ size: CGSize
    ) -> (point: CGPoint, outward: CGPoint) {
        let w = size.width
        let h = size.height
        switch side {
        case .top: return (CGPoint(x: w * along, y: 0), CGPoint(x: 0, y: -1))
        case .right: return (CGPoint(x: w, y: h * along), CGPoint(x: 1, y: 0))
        case .bottom: return (CGPoint(x: w * (1 - along), y: h), CGPoint(x: 0, y: 1))
        case .left: return (CGPoint(x: 0, y: h * (1 - along)), CGPoint(x: -1, y: 0))
        }
    }

    /// A curve from `start` to `end` that sags sideways by `bow` of its length near its start
    /// and swings back a little near its end, as something alive rather than a drawn arc.
    private static func bowed(
        from start: CGPoint, to end: CGPoint, bow: CGFloat
    ) -> SymbioteGeometry.Centerline {
        let chord = end - start
        let across = CGPoint(x: -chord.y, y: chord.x).normalized * (bow * bowShare * chord.length)
        let first = start + chord * (1.0 / 3) + across * bowLead
        let second = start + chord * (2.0 / 3) - across * bowReturn
        return SymbioteGeometry.Centerline(points: (0..<sampleCount).map { i in
            let t = CGFloat(i) / CGFloat(sampleCount - 1)
            let u = 1 - t
            return start * (u * u * u) + first * (3 * u * u * t) + second * (3 * u * t * t) + end * (t * t * t)
        })
    }

    /// From just outside its edge, along a bowed curve toward the middle.
    private static func strand(_ blueprint: Blueprint, _ size: CGSize) -> Strand {
        let (rootPoint, outward) = edgePoint(blueprint.side, blueprint.along, size)
        let shorter = min(size.width, size.height)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let inward = centre - rootPoint
        let side = CGPoint(x: -inward.y, y: inward.x).normalized
        let heading = centre + inward * (pastCore + pastCorePerWeight * blueprint.weight)
            + side * (blueprint.aim * aimShare * shorter)
        let end = rootPoint + (heading - rootPoint) * blueprint.depth
        let line = bowed(from: rootPoint + outward * rootOutset, to: end, bow: blueprint.bow)
        var lit = side
        let light = SymbioteGeometry.lightDirection
        if lit.x * light.x + lit.y * light.y < 0 { lit = lit * -1 }
        return Strand(
            line: line, total: line.lengths[line.lengths.count - 1], flare: flareShare * shorter,
            lit: lit)
    }

    /// The samples of `line` up to `length`, ending exactly there.
    private static func prefix(
        of line: SymbioteGeometry.Centerline, upTo length: CGFloat
    ) -> (points: [CGPoint], lengths: [CGFloat]) {
        var points: [CGPoint] = []
        var lengths: [CGFloat] = []
        for i in line.points.indices where line.lengths[i] < length - 0.5 {
            points.append(line.points[i])
            lengths.append(line.lengths[i])
        }
        points.append(SymbioteGeometry.point(on: line, at: length))
        lengths.append(length)
        return (points, lengths)
    }

    /// The samples of `line` from `length` on, starting exactly there.
    private static func suffix(
        of line: SymbioteGeometry.Centerline, from length: CGFloat
    ) -> (points: [CGPoint], lengths: [CGFloat]) {
        var points = [SymbioteGeometry.point(on: line, at: length)]
        var lengths = [length]
        for i in line.points.indices where line.lengths[i] > length + 0.5 {
            points.append(line.points[i])
            lengths.append(line.lengths[i])
        }
        return (points, lengths)
    }

    /// A ribbon whose root end reaches back out of the tile by its own radius, so the cut end
    /// is always outside, where the clip removes it, and the root meets the edge round. With
    /// `bothEnds`, its far end does the same.
    private static func rooted(_ points: [CGPoint], _ radii: [CGFloat], bothEnds: Bool = false) -> [CGPoint] {
        var points = points
        var radii = radii
        let back = (points[0] - points[1]).normalized
        points.insert(points[0] + back * radii[0], at: 0)
        radii.insert(radii[0], at: 0)
        if bothEnds, let last = points.last, let lastRadius = radii.last {
            points.append(last + (last - points[points.count - 2]).normalized * lastRadius)
            radii.append(lastRadius)
        }
        return SymbioteGeometry.ribbon(points, radii)
    }

    /// `1` plus the sum of `lumps` at `angle`: the wobble of an outline.
    private static func wobble(
        _ angle: CGFloat, _ lumps: [(depth: CGFloat, waves: CGFloat, phase: CGFloat)]
    ) -> CGFloat {
        lumps.reduce(1) { $0 + $1.depth * sin($1.waves * angle + $1.phase) }
    }

    /// The lumpy core the strands land on; `scale` 0...1.
    private static func core(_ size: CGSize, scale: CGFloat) -> [CGPoint] {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radii = CGSize(width: size.width * coreShare * scale, height: size.height * coreShare * scale)
        return wound((0..<coreSamples).map { i in
            let angle = CGFloat(i) / CGFloat(coreSamples) * 2 * .pi
            return centre + CGPoint(x: cos(angle) * radii.width, y: sin(angle) * radii.height)
                * wobble(angle, coreLumps)
        })
    }

    // MARK: Opening

    /// How far the hole has spread, as its half-axes in halves of the tile's sides.
    private static func hole(_ progress: CGFloat) -> CGSize {
        func spread(by end: CGFloat) -> CGFloat {
            holeReach * (1 - pow(1 - min(max(progress / end, 0), 1), holeEase))
        }
        return CGSize(width: spread(by: holeEnd), height: spread(by: runEnd))
    }

    /// What is left of the cover: one quad per ray from the tear, between the hole's outline
    /// and the clip box. Built as rays rather than a ring with a hole, so the hole may grow
    /// past the box without turning the cover inside out; the box's corners are rays of their
    /// own, so none of them is cut off.
    private static func cover(_ size: CGSize, hole: CGSize) -> [[CGPoint]] {
        let box = CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin)
        let centre = CGPoint(x: size.width * tearCentre.x, y: size.height * tearCentre.y)
        var angles = (0..<holeSamples).map { CGFloat($0) / CGFloat(holeSamples) * 2 * .pi }
        for corner in [
            CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
            CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY),
        ] {
            let angle = atan2(corner.y - centre.y, corner.x - centre.x)
            angles.append(angle < 0 ? angle + 2 * .pi : angle)
        }
        angles.sort()
        let halfAxes = CGSize(
            width: max(size.width / 2 * hole.width, 0.01), height: max(size.height / 2 * hole.height, 0.01))
        let rays = angles.map { angle -> (inner: CGPoint, outer: CGPoint) in
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let outer = centre + direction * distanceToBox(from: centre, along: direction, box)
            let reach = wobble(angle, holeLumps) / ellipseNorm(direction, halfAxes)
            let edge = centre + direction * reach
            let inner = reach < outer.distance(to: centre) ? edge : outer
            return (inner, outer)
        }
        var quads: [[CGPoint]] = []
        for i in rays.indices {
            let a = rays[i]
            let b = rays[(i + 1) % rays.count]
            // A ray whose hole has passed the box leaves nothing between it and the next.
            guard a.inner != a.outer || b.inner != b.outer else { continue }
            quads.append(wound([a.inner, a.outer, b.outer, b.inner]))
        }
        return quads
    }

    /// How far a ray from `point` inside `box` runs before it leaves it.
    private static func distanceToBox(from point: CGPoint, along direction: CGPoint, _ box: CGRect) -> CGFloat {
        var distance = CGFloat.greatestFiniteMagnitude
        if direction.x > 1e-6 { distance = min(distance, (box.maxX - point.x) / direction.x) }
        if direction.x < -1e-6 { distance = min(distance, (box.minX - point.x) / direction.x) }
        if direction.y > 1e-6 { distance = min(distance, (box.maxY - point.y) / direction.y) }
        if direction.y < -1e-6 { distance = min(distance, (box.minY - point.y) / direction.y) }
        return distance
    }

    /// The length of the unit vector `direction` measured in half-axes: one over the distance
    /// to an ellipse of those half-axes along it.
    private static func ellipseNorm(_ direction: CGPoint, _ halfAxes: CGSize) -> CGFloat {
        let x = direction.x / halfAxes.width
        let y = direction.y / halfAxes.height
        return max((x * x + y * y).squareRoot(), 1e-6)
    }

    /// One rope across the hole: whole and thinning until it snaps, then its two halves
    /// pulling back to their edges with a bead on each torn end.
    private static func rope(_ bridge: Bridge, index: Int, size: CGSize, progress: CGFloat) -> SymbioteFrame {
        var frame = SymbioteFrame()
        let shorter = min(size.width, size.height)
        let (a, outA) = edgePoint(bridge.from.side, bridge.from.along, size)
        let (b, outB) = edgePoint(bridge.to.side, bridge.to.along, size)
        let line = bowed(from: a + outA * rootOutset, to: b + outB * rootOutset, bow: bridge.bow)
        let total = line.lengths[line.lengths.count - 1]
        let flare = flareShare * shorter
        let root = bridge.weight * ropeRoot
        let fullNeck = bridge.weight * ropeNeck
        // Stretched by the widening hole, the rope thins until it snaps.
        let neck = max(minimumRadius, fullNeck * lerp(1, stretchedNeck, smoothstep(0, bridge.snap, progress)))
        func whole(_ s: CGFloat) -> CGFloat {
            // Swells into the cover at both ends, as the drag effect's bridges do into the bodies.
            neck + max(root - neck, 0) * min(exp(-s / flare) + exp(-(total - s) / flare), 1) * lump(s, index)
        }
        let tearAt = total * bridge.tear
        let pinching = min(max((progress - bridge.snap) / pinchSpan, 0), 1)
        // From `snap` on it pinches through where it tears, as the drag effect's strands do.
        let pinch = 1 - pow(1 - pinching, pinchEase)
        func pinched(_ s: CGFloat) -> CGFloat {
            let fromTear = (s - tearAt) / pinchWidth
            return whole(s) * (1 - pinch * exp(-fromTear * fromTear))
        }
        guard pinching >= 1 else {
            frame.ribbons.append(rooted(line.points, line.lengths.map(pinched), bothEnds: true))
            return frame
        }
        // Snapped: each half pulls back to its edge, fast at first, its root letting go last.
        let back = smoothstep(0, 1, (progress - bridge.snap - pinchSpan) / recoilSpan)
        let pull = 1 - (1 - back) * (1 - back)
        let tip = tipRadius(neck)
        // A half's thickness `fromRoot` along it: the stub's taper, never more than the torn rope.
        func half(_ s: CGFloat, fromRoot: CGFloat, full: CGFloat, fade: CGFloat) -> CGFloat {
            let along = fromRoot / max(full, 1)
            let stub = tip + (root - tip) * (1 - along) * (1 - along) * lump(s, index)
            return min(pinched(s), stub) * fade
        }
        let lengthA = tearAt * (1 - pull)
        if lengthA > 0.5 {
            let fade = min(1, lengthA / meltLength)
            let (points, lengths) = prefix(of: line, upTo: lengthA)
            let radii = lengths.map { half($0, fromRoot: $0, full: tearAt, fade: fade) }
            appendStub(to: &frame, points, radii, bead: beadShare * tip * fade)
        }
        let lengthB = (total - tearAt) * (1 - pull)
        if lengthB > 0.5 {
            let fade = min(1, lengthB / meltLength)
            let (points, lengths) = suffix(of: line, from: total - lengthB)
            let radii = lengths.map { half($0, fromRoot: total - $0, full: total - tearAt, fade: fade) }
            appendStub(to: &frame, points.reversed(), radii.reversed(), bead: beadShare * tip * fade)
        }
        return frame
    }

    /// Half a snapped rope, from its edge to its torn end, with a bead balled up on that end.
    private static func appendStub(
        to frame: inout SymbioteFrame, _ points: [CGPoint], _ radii: [CGFloat], bead: CGFloat
    ) {
        guard points.count >= 2 else { return }
        frame.ribbons.append(rooted(points, radii))
        if bead > minimumBead { frame.droplets.append(.init(center: points[points.count - 1], radius: bead)) }
    }

    // MARK: Cover

    /// The cocoon's wet look, fixed on the cover and drawn in shares of the tile: slivers where
    /// the light falls (up and to the left) and a soft rim along the far side, so the black
    /// reads as a rounded body. `scale` 0...1 thins them in and out without moving them.
    private static func glints(_ size: CGSize, scale: CGFloat) -> [[CGPoint]] {
        guard scale > 0.02 else { return [] }
        let unit = min(size.width, size.height) / 64
        func sliver(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, width: CGFloat) -> [CGPoint] {
            let count = 14
            var points: [CGPoint] = []
            var widths: [CGFloat] = []
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count - 1)
                let p = a * ((1 - t) * (1 - t)) + b * (2 * t * (1 - t)) + c * (t * t)
                points.append(CGPoint(x: p.x * size.width, y: p.y * size.height))
                widths.append(max(width * unit * scale * sin(.pi * t), 0.12))
            }
            return SymbioteGeometry.ribbon(points, widths)
        }
        return [
            // The light's reflection round the upper left shoulder, and a fainter one inside it.
            sliver(CGPoint(x: 0.14, y: 0.50), CGPoint(x: 0.14, y: 0.20), CGPoint(x: 0.44, y: 0.09), width: 2.5),
            sliver(CGPoint(x: 0.26, y: 0.40), CGPoint(x: 0.27, y: 0.28), CGPoint(x: 0.40, y: 0.21), width: 1.3),
            // A glint on the crown.
            sliver(CGPoint(x: 0.60, y: 0.075), CGPoint(x: 0.66, y: 0.07), CGPoint(x: 0.72, y: 0.08), width: 1.0),
            // Light thrown back round the far, lower right side.
            sliver(CGPoint(x: 0.36, y: 0.955), CGPoint(x: 0.94, y: 0.955), CGPoint(x: 0.94, y: 0.58), width: 0.8),
        ]
    }

    private static func rectangle(_ rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    /// The same winding as every ribbon, so overlapping shapes never punch holes in each other.
    private static func wound(_ polygon: [CGPoint]) -> [CGPoint] {
        SymbioteGeometry.signedArea(polygon) > 0 ? polygon.reversed() : polygon
    }

    // MARK: Clipping

    /// The goo cut to the tile grown by `margin`, and its light to the tile itself: a sheen on
    /// goo past the tile's edge would float on the island's black. A cut keeps each shape's
    /// winding; a bead near the cut shrinks to fit inside it, as a stub's does melting into
    /// its edge.
    private static func clipped(_ frame: SymbioteFrame, _ size: CGSize) -> SymbioteFrame {
        let tile = CGRect(origin: .zero, size: size)
        let box = tile.insetBy(dx: -margin, dy: -margin)
        func cut(_ polygons: [[CGPoint]], to rect: CGRect) -> [[CGPoint]] {
            polygons.map { clip($0, to: rect) }.filter { $0.count >= 3 }
        }
        let droplets = frame.droplets.compactMap { droplet -> SymbioteFrame.Droplet? in
            let c = droplet.center
            let room = min(c.x - box.minX, box.maxX - c.x, c.y - box.minY, box.maxY - c.y)
            let radius = min(droplet.radius, room)
            return radius > minimumBead ? .init(center: c, radius: radius) : nil
        }
        return SymbioteFrame(
            ribbons: cut(frame.ribbons, to: box), droplets: droplets,
            highlights: cut(frame.highlights, to: tile))
    }

    /// Sutherland-Hodgman against each side of `rect` in turn.
    private static func clip(_ polygon: [CGPoint], to rect: CGRect) -> [CGPoint] {
        let sides: [(CGPoint) -> CGFloat] = [
            { $0.x - rect.minX }, { rect.maxX - $0.x }, { $0.y - rect.minY }, { rect.maxY - $0.y },
        ]
        var output = polygon
        for inside in sides {
            guard var previous = output.last else { return [] }
            let input = output
            output = []
            for current in input {
                let a = inside(previous)
                let b = inside(current)
                if (a >= 0) != (b >= 0) {
                    output.append(previous + (current - previous) * (a / (a - b)))
                }
                if b >= 0 { output.append(current) }
                previous = current
            }
        }
        return output
    }

    // MARK: Coverage

    /// Share of the tile under goo, sampled on a grid (nonzero rule for ribbons, discs for droplets).
    /// Samples sit at the centres of `step`-sized cells, so the rows and columns nearest the
    /// edges and corners are always among them.
    public static func coverage(of frame: SymbioteFrame, size: CGSize, step: CGFloat = 4) -> Double {
        guard size.width > 0, size.height > 0, step > 0 else { return 0 }
        let columns = max(1, Int((size.width / step).rounded(.up)))
        let rows = max(1, Int((size.height / step).rounded(.up)))
        let boxes = frame.ribbons.map(bounds)
        var covered = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(
                    x: (CGFloat(column) + 0.5) * size.width / CGFloat(columns),
                    y: (CGFloat(row) + 0.5) * size.height / CGFloat(rows))
                let inDroplet = frame.droplets.contains { $0.center.distance(to: point) <= $0.radius }
                let inRibbon = frame.ribbons.indices.contains { i in
                    boxes[i].contains(point) && winding(of: frame.ribbons[i], around: point) != 0
                }
                if inDroplet || inRibbon { covered += 1 }
            }
        }
        return Double(covered) / Double(rows * columns)
    }

    private static func bounds(_ polygon: [CGPoint]) -> CGRect {
        let xs = polygon.map(\.x)
        let ys = polygon.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
        else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// How many times the outline winds round `point` (Sunday's crossing rule).
    private static func winding(of polygon: [CGPoint], around point: CGPoint) -> Int {
        guard var a = polygon.last else { return 0 }
        var winding = 0
        for b in polygon {
            let side = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
            if a.y <= point.y {
                if b.y > point.y, side > 0 { winding += 1 }
            } else if b.y <= point.y, side < 0 {
                winding -= 1
            }
            a = b
        }
        return winding
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}
