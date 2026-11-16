import CoreGraphics
import Foundation

/// The goo that swallows a file tile while it converts: a pure function of the phase, so any
/// frame can be drawn on its own.
///
/// Strands creep in from all four edges with thin, beaded tips and cross past the centre; their
/// roots swell until the union closes into a glossy cocoon. At the reveal the cover pinches in
/// the middle, as a strand tears in the drag effect: the half on each edge snaps back to it, the
/// far half recoils the other way and melts, and the roots go last. Drawn by the same canvas as
/// the drag's strands (blur 5, alpha threshold 0.5, then the crisp shapes), so shapes closer than
/// about 10 pt web together and anything thinner than about 1.3 pt shows only in the crisp layer.
/// Coverage only grows during the engulf and only shrinks during the reveal, give or take a
/// moving bead.
public enum SymbioteEngulf {
    /// How far goo may bulge past the tile; the canvas is this much larger on every side.
    public static let overhang: CGFloat = 10
    /// The strands that reach in, three from each side.
    public static let strandCount = 12

    // MARK: Tuning

    /// Goo is cut this far outside the tile: half the 8 pt gap to the next tile, so it never
    /// darkens a neighbour. The canvas's larger overhang leaves the blur room around it.
    static let margin: CGFloat = 4
    /// Strands start this far outside the edge they root on, so they enter the tile already round.
    static let rootOutset: CGFloat = 4
    /// Points along each strand's curve.
    static let sampleCount = 32
    /// Every strand takes this share of the progress to reach across, after its delay.
    static let reachSpan = 0.62
    /// Root radius while the strands creep in; it swells to `rootShare` of the shorter side.
    static let rootStart: CGFloat = 3
    static let rootShare: CGFloat = 0.6
    /// Radius of the thin part of a strand, before and after it thickens.
    static let neckStart: CGFloat = 1.8
    static let neckEnd: CGFloat = 4.5
    /// Length over which a strand narrows into its tip.
    static let tipLength: CGFloat = 16
    /// How far into the tile a root's swelling reaches, as a share of the shorter side: the
    /// roots hold the edges, so the middle is held only by necks and the centre, which the
    /// reveal can then visibly pinch open.
    static let flareShare: CGFloat = 0.2
    /// Strands at least this heavy carry a sheen once their roots are this thick.
    static let sheenWeight: CGFloat = 0.85
    static let sheenRoot: CGFloat = 4
    /// The centre fills in from this progress on, out to this share of the tile.
    static let blobStart: CGFloat = 0.55
    static let blobShare: CGFloat = 0.4
    /// How far the cover rectangle reaches past the tile once it is closed.
    static let coverOutset: CGFloat = 2
    /// Share of the reveal over which the cover pinches through in the middle.
    static let pinchSpan = 0.16
    /// Half width of the pinch along a strand, as in the drag effect's tear.
    static let pinchWidth: CGFloat = 9
    /// Every stub is back at its edge by this share of the reveal.
    static let retractEnd = 0.97
    /// Share of the reveal the far half of a torn strand takes to recoil and melt.
    static let farRecoil = 0.3

    private enum Side { case top, right, bottom, left }

    private struct Blueprint {
        var side: Side
        var along: CGFloat   // where on that side, 0...1, running clockwise round the tile
        var delay: Double    // share of the progress before it sets off, 0...0.28
        var bow: CGFloat     // sideways sag, -1...1
        var aim: CGFloat     // how far to one side of the centre it heads, -1...1
        var weight: CGFloat  // thickness relative to the heaviest strand
    }

    private static let blueprints: [Blueprint] = [
        // Three per side, a little off even spacing. Light feelers set off first; one heavy
        // trunk per side follows, as the drag effect's island feels before it grabs. The trunks
        // sit at different places on their sides, so their sheens never line up into a cross.
        Blueprint(side: .top, along: 0.14, delay: 0.20, bow: 0.6, aim: 0.7, weight: 1.00),
        Blueprint(side: .top, along: 0.52, delay: 0.05, bow: -0.4, aim: -0.5, weight: 0.62),
        Blueprint(side: .top, along: 0.86, delay: 0.00, bow: -0.9, aim: 0.2, weight: 0.70),
        Blueprint(side: .right, along: 0.16, delay: 0.12, bow: 0.8, aim: -0.8, weight: 0.66),
        Blueprint(side: .right, along: 0.49, delay: 0.03, bow: -0.3, aim: 0.6, weight: 0.72),
        Blueprint(side: .right, along: 0.83, delay: 0.26, bow: 0.7, aim: 0.1, weight: 0.94),
        Blueprint(side: .bottom, along: 0.12, delay: 0.17, bow: -0.7, aim: 0.5, weight: 0.60),
        Blueprint(side: .bottom, along: 0.47, delay: 0.28, bow: 0.5, aim: -0.7, weight: 0.98),
        Blueprint(side: .bottom, along: 0.85, delay: 0.08, bow: -0.5, aim: 0.9, weight: 0.68),
        Blueprint(side: .left, along: 0.18, delay: 0.10, bow: 0.9, aim: -0.4, weight: 0.76),
        Blueprint(side: .left, along: 0.53, delay: 0.02, bow: -0.6, aim: 0.8, weight: 0.76),
        Blueprint(side: .left, along: 0.87, delay: 0.23, bow: 0.4, aim: -0.6, weight: 0.90),
    ]

    /// One strand's fixed path across a tile.
    private struct Strand {
        var line: SymbioteGeometry.Centerline
        var total: CGFloat
        /// Arc length where the strand passes closest to the tile's centre: where it tears.
        var middle: CGFloat
        /// Arc length over which the root's swelling falls off.
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
        frame.highlights += glints(size, scale: smoothstep(0.75, 1, progress))
        return clipped(frame, size)
    }

    /// The closed cover: the strands at full thickness, the filled centre, and the tile's
    /// rectangle under them, so full cover is a fact rather than a hope.
    private static func cocoon(_ size: CGSize) -> SymbioteFrame {
        var frame = goo(size, 1)
        frame.ribbons.append(wound(rectangle(CGRect(origin: .zero, size: size)
            .insetBy(dx: -coverOutset, dy: -coverOutset))))
        frame.highlights += glints(size, scale: 1)
        return clipped(frame, size)
    }

    /// The strands and the centre at engulf progress `progress`.
    private static func goo(_ size: CGSize, _ progress: CGFloat) -> SymbioteFrame {
        var frame = SymbioteFrame()
        let grow = smoothstep(0.3, 1, progress)
        for (index, blueprint) in blueprints.enumerated() {
            let reach = reachProgress(blueprint, progress)
            guard reach > 0 else { continue }
            let strand = strand(blueprint, size)
            let neck = blueprint.weight * lerp(neckStart, neckEnd, smoothstep(0.15, 1, progress))
            let root = blueprint.weight * lerp(rootStart, rootShare * min(size.width, size.height), grow)
            let length = strand.total * reach
            let (points, lengths) = prefix(of: strand.line, upTo: length)
            guard points.count >= 2 else { continue }
            let tip = max(0.6 * neck, 0.8)
            let radii = lengths.map { s -> CGFloat in
                let body = body(s, strand: strand, root: root, neck: neck, index: index)
                // Fixed in arc length, so a point of the strand only ever gets thicker.
                return tip + (body - tip) * smoothstep(0, tipLength, length - s)
            }
            frame.ribbons.append(rooted(points, radii))
            // A bead at the tip, as on the drag effect's feelers.
            frame.droplets.append(.init(center: points[points.count - 1], radius: max(1.5 * neck, 1.5)))
            // The ropes' sheen gives way to the cocoon's own glints as the strands merge.
            let shine = 1 - smoothstep(0.6, 0.85, progress)
            if blueprint.weight >= sheenWeight, root >= sheenRoot, shine > 0.05,
                let sheen = SymbioteGeometry.sheen(
                    points, sheenRadii(radii, neck: neck), minimumWidth: 0.12, widthScale: shine,
                    facing: strand.lit)
            {
                frame.highlights.append(sheen)
            }
        }
        let fill = smoothstep(blobStart, 1, progress)
        if fill > 0 { frame.ribbons.append(blob(size, scale: fill)) }
        return frame
    }

    /// The cover splitting. Every strand pinches through where it passes the middle, as a strand
    /// tears in the drag effect; the half on its edge snaps back to it while the far half recoils
    /// the other way and melts. The centre drains first and the roots thin last.
    private static func reveal(_ size: CGSize, _ progress: CGFloat) -> SymbioteFrame {
        var frame = SymbioteFrame()
        let pinch = 1 - pow(1 - min(progress / CGFloat(pinchSpan), 1), 0.7)
        // The roots let go slowly the whole time and are the last thing left.
        let hold = 1 - 0.5 * smoothstep(0.25, CGFloat(retractEnd), progress)
        // The stubs' sheen comes in once the cover has opened enough for them to read as stubs.
        let shine = smoothstep(0.2, 0.4, progress)
        for (index, blueprint) in blueprints.enumerated() {
            let strand = strand(blueprint, size)
            let neck = blueprint.weight * neckEnd
            let root = blueprint.weight * rootShare * min(size.width, size.height)
            func pinched(_ s: CGFloat) -> CGFloat {
                let fromMiddle = (s - strand.middle) / pinchWidth
                let full = fullRadius(s, strand: strand, root: root, neck: neck, index: index)
                return full * (1 - pinch * exp(-fromMiddle * fromMiddle))
            }
            // Strands that came last let go first; each snaps back fast, then slows.
            let start = 0.06 + (0.28 - blueprint.delay) * 0.5
            let t = min(max((Double(progress) - start) / (retractEnd - start), 0), 1)

            // The half on the edge. Measured from the tile's edge: the part outside is never seen.
            let inside = (strand.middle - rootOutset) * CGFloat(pow(1 - t, 1.3))
            let length = rootOutset + inside
            // A stub melts into its edge as it gets short.
            let fade = min(1, inside / 12)
            if fade > 0.02 {
                let (points, lengths) = prefix(of: strand.line, upTo: length)
                let radii = lengths.map { s -> CGFloat in
                    // The stub's taper, as in the drag effect: thick at its root, thin at its tip.
                    let along = s / length
                    let stub = neck + (root * hold - neck) * (1 - along) * (1 - along) * lump(s, index)
                    return min(pinched(s), stub) * fade
                }
                frame.ribbons.append(rooted(points, radii))
                appendBead(to: &frame, at: points[points.count - 1], ribbonRadius: radii[radii.count - 1])
                if blueprint.weight >= sheenWeight, root * fade >= sheenRoot, shine > 0.05,
                    let sheen = SymbioteGeometry.sheen(
                        points, sheenRadii(radii, neck: neck * fade), minimumWidth: 0.12,
                        widthScale: shine, facing: strand.lit)
                {
                    frame.highlights.append(sheen)
                }
            }

            // The far half, pulled the other way, thinning as it goes.
            let recoil = min(max((Double(progress) - start) / farRecoil, 0), 1)
            let free = strand.middle + (strand.total - strand.middle) * CGFloat(1 - (1 - recoil) * (1 - recoil))
            let farFade = min(1, (strand.total - free) / 12)
            if farFade > 0.02 {
                let (points, lengths) = suffix(of: strand.line, from: free)
                if points.count >= 2 {
                    let radii = lengths.map { pinched($0) * farFade }
                    frame.ribbons.append(SymbioteGeometry.ribbon(points, radii))
                    appendBead(to: &frame, at: points[0], ribbonRadius: radii[0])
                }
            }
        }
        // The centre drains first, so the middle the strands pinch through actually opens.
        let fill = 1 - smoothstep(0, 0.12, progress)
        if fill > 0.01 { frame.ribbons.append(blob(size, scale: fill)) }
        frame.highlights += glints(size, scale: 1 - smoothstep(0, 0.2, progress))
        return clipped(frame, size)
    }

    /// A torn end balls up into a bead a little wider than the strand, as in the drag effect.
    private static func appendBead(to frame: inout SymbioteFrame, at center: CGPoint, ribbonRadius: CGFloat) {
        let radius = 1.25 * ribbonRadius
        if radius > 0.4 { frame.droplets.append(.init(center: center, radius: radius)) }
    }

    // MARK: Strands

    /// How far a strand has reached across, 0...1: it shoots in and slows as it arrives.
    private static func reachProgress(_ blueprint: Blueprint, _ progress: CGFloat) -> CGFloat {
        let t = min(max((Double(progress) - blueprint.delay) / reachSpan, 0), 1)
        return CGFloat(1 - pow(1 - t, 3))
    }

    /// The thickness a strand would have at `s` with nothing tapering it: its root swells into
    /// the tile near the edge, the rest stays near the neck, and it is slightly lumpy, like
    /// something organic rather than a drawn line.
    private static func body(
        _ s: CGFloat, strand: Strand, root: CGFloat, neck: CGFloat, index: Int
    ) -> CGFloat {
        neck + (root - neck) * exp(-s / strand.flare) * lump(s, index)
    }

    /// The radii a sheen follows: the rope, not the root's swelling, whose steep flare would
    /// fold the sliver into a chevron.
    private static func sheenRadii(_ radii: [CGFloat], neck: CGFloat) -> [CGFloat] {
        radii.map { min($0, 2.5 * neck) }
    }

    /// Fixed along the strand, so the lumps swell with it rather than slide.
    private static func lump(_ s: CGFloat, _ index: Int) -> CGFloat {
        1 + 0.1 * sin(s / 5 + CGFloat(index) * 1.7)
    }

    /// A strand's thickness in the closed cocoon.
    private static func fullRadius(
        _ s: CGFloat, strand: Strand, root: CGFloat, neck: CGFloat, index: Int
    ) -> CGFloat {
        let tip = max(0.6 * neck, 0.8)
        let body = body(s, strand: strand, root: root, neck: neck, index: index)
        return tip + (body - tip) * smoothstep(0, tipLength, strand.total - s)
    }

    /// From just outside its edge, along a bowed curve through the tile to past the centre.
    private static func strand(_ blueprint: Blueprint, _ size: CGSize) -> Strand {
        let w = size.width
        let h = size.height
        let rootPoint: CGPoint
        let outward: CGPoint
        switch blueprint.side {
        case .top:
            rootPoint = CGPoint(x: w * blueprint.along, y: 0)
            outward = CGPoint(x: 0, y: -1)
        case .right:
            rootPoint = CGPoint(x: w, y: h * blueprint.along)
            outward = CGPoint(x: 1, y: 0)
        case .bottom:
            rootPoint = CGPoint(x: w * (1 - blueprint.along), y: h)
            outward = CGPoint(x: 0, y: 1)
        case .left:
            rootPoint = CGPoint(x: 0, y: h * (1 - blueprint.along))
            outward = CGPoint(x: -1, y: 0)
        }
        let center = CGPoint(x: w / 2, y: h / 2)
        let start = rootPoint + outward * rootOutset
        // Heavier strands reach further past the centre, and each heads a little to one side
        // of it, so the strands cross one another as a web rather than meet in a star.
        let inward = center - rootPoint
        let side = CGPoint(x: -inward.y, y: inward.x).normalized
        let end = center + inward * (0.15 + 0.3 * blueprint.weight)
            + side * (blueprint.aim * 0.18 * min(w, h))
        let chord = end - start
        let across = CGPoint(x: -chord.y, y: chord.x).normalized
        let control = (start + end) * 0.5 + across * (blueprint.bow * 0.16 * chord.length)
        let points = (0..<sampleCount).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(sampleCount - 1)
            return start * ((1 - t) * (1 - t)) + control * (2 * t * (1 - t)) + end * (t * t)
        }
        let line = SymbioteGeometry.Centerline(points: points)
        let nearest = points.indices.min {
            points[$0].distance(to: center) < points[$1].distance(to: center)
        } ?? 0
        var lit = across
        let light = SymbioteGeometry.lightDirection
        if lit.x * light.x + lit.y * light.y < 0 { lit = lit * -1 }
        return Strand(
            line: line, total: line.lengths[line.lengths.count - 1], middle: line.lengths[nearest],
            flare: flareShare * min(w, h), lit: lit)
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
    /// is always outside, where the clip removes it, and the root meets the edge round.
    private static func rooted(_ points: [CGPoint], _ radii: [CGFloat]) -> [CGPoint] {
        let back = (points[0] - points[1]).normalized
        return SymbioteGeometry.ribbon([points[0] + back * radii[0]] + points, [radii[0]] + radii)
    }

    // MARK: Cover

    /// The lumpy filling of the centre; `scale` 0...1.
    private static func blob(_ size: CGSize, scale: CGFloat) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radii = CGSize(width: size.width * blobShare * scale, height: size.height * blobShare * scale)
        let count = 40
        return wound((0..<count).map { i in
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi
            let lump = 1 + 0.07 * sin(3 * angle + 0.6) + 0.04 * sin(5 * angle + 2.1)
            return center + CGPoint(x: cos(angle) * radii.width, y: sin(angle) * radii.height) * lump
        })
    }

    /// The cocoon's wet look, fixed on the cover: three slivers where the light falls (up and to
    /// the left) and a faint rim along the far side. `scale` 0...1 thins them in and out.
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
            sliver(CGPoint(x: 0.14, y: 0.52), CGPoint(x: 0.14, y: 0.20), CGPoint(x: 0.44, y: 0.09), width: 2.2),
            sliver(CGPoint(x: 0.26, y: 0.40), CGPoint(x: 0.27, y: 0.28), CGPoint(x: 0.40, y: 0.21), width: 1.3),
            sliver(CGPoint(x: 0.60, y: 0.075), CGPoint(x: 0.66, y: 0.07), CGPoint(x: 0.72, y: 0.08), width: 1.0),
            sliver(CGPoint(x: 0.22, y: 0.955), CGPoint(x: 0.95, y: 0.96), CGPoint(x: 0.94, y: 0.50), width: 0.5),
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

    /// Everything cut to the tile grown by `margin`; a cut keeps each shape's winding.
    private static func clipped(_ frame: SymbioteFrame, _ size: CGSize) -> SymbioteFrame {
        let box = CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin)
        func cut(_ polygons: [[CGPoint]]) -> [[CGPoint]] {
            polygons.map { clip($0, to: box) }.filter { $0.count >= 3 }
        }
        return SymbioteFrame(
            ribbons: cut(frame.ribbons),
            droplets: frame.droplets.filter { box.contains($0.center) },
            highlights: cut(frame.highlights))
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
