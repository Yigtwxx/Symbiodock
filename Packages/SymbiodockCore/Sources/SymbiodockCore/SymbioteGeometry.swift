import CoreGraphics
import Foundation

/// Shape builders shared by the goo effects: the strands of a drag (`SymbioteSimulation`) and
/// the goo that swallows a file tile (`SymbioteEngulf`). Both are drawn by the same canvas, so
/// they turn a curve and its radii into polygons the same way and catch the light the same way.
enum SymbioteGeometry {
    /// Where the light comes from, for the sheen: up and to the left.
    static let lightDirection = CGPoint(x: -0.6, y: -0.8)

    /// Points along a curve, with the arc length at each one.
    struct Centerline {
        var points: [CGPoint]
        var lengths: [CGFloat]

        /// Measures the arc length along `points`.
        init(points: [CGPoint]) {
            var lengths: [CGFloat] = [0]
            for i in points.indices.dropFirst() {
                lengths.append(lengths[i - 1] + points[i - 1].distance(to: points[i]))
            }
            self.points = points
            self.lengths = lengths
        }
    }

    /// A smooth curve through the nodes (Catmull-Rom), sampled at `samples` points.
    static func centerline(_ nodes: [CGPoint], samples: Int) -> Centerline {
        var points: [CGPoint] = []
        let segments = nodes.count - 1
        for sample in 0..<samples {
            let t = CGFloat(sample) / CGFloat(samples - 1) * CGFloat(segments)
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
        return Centerline(points: points)
    }

    /// The point `length` along the curve; its last point when `length` is past the end.
    static func point(on line: Centerline, at length: CGFloat) -> CGPoint {
        for i in 1..<line.points.count where line.lengths[i] >= length {
            let span = line.lengths[i] - line.lengths[i - 1]
            let t = span > 0 ? (length - line.lengths[i - 1]) / span : 0
            return line.points[i - 1] + (line.points[i] - line.points[i - 1]) * t
        }
        return line.points.last ?? .zero
    }

    /// A thin sliver along the lit side of a strand, fading out toward both ends.
    /// - Parameters:
    ///   - minimumWidth: the sliver never gets thinner than this, so it does not break up.
    ///   - widthScale: thins the sliver in place, to fade it in or out without moving it.
    ///   - facing: when set, the side the sliver keeps all along the strand. Without it each
    ///     point turns to the light on its own, and a strand running along the light would
    ///     throw its sliver from side to side.
    static func sheen(
        _ points: [CGPoint], _ radii: [CGFloat], minimumWidth: CGFloat, widthScale: CGFloat = 1,
        facing: CGPoint? = nil
    ) -> [CGPoint]? {
        sliver(
            points, radii, side: 1, inset: 0.42, width: 0.2, minimumWidth: minimumWidth,
            widthScale: widthScale, facing: facing ?? lightDirection)
    }

    /// A fainter line along the far side, which makes the strand read as round.
    static func rimLight(_ points: [CGPoint], _ radii: [CGFloat], minimumWidth: CGFloat) -> [CGPoint]? {
        sliver(
            points, radii, side: -1, inset: 0.62, width: 0.07, minimumWidth: minimumWidth,
            widthScale: 1, facing: lightDirection)
    }

    private static func sliver(
        _ points: [CGPoint], _ radii: [CGFloat], side: CGFloat, inset: CGFloat, width: CGFloat,
        minimumWidth: CGFloat, widthScale: CGFloat, facing: CGPoint
    ) -> [CGPoint]? {
        let skip = points.count / 6
        let range = skip..<(points.count - skip)
        guard range.count >= 3 else { return nil }
        var shifted: [CGPoint] = []
        var widths: [CGFloat] = []
        for i in range {
            let tangent = (points[min(i + 1, points.count - 1)] - points[max(i - 1, 0)]).normalized
            var normal = CGPoint(x: -tangent.y, y: tangent.x)
            if normal.x * facing.x + normal.y * facing.y < 0 {
                normal = normal * -1
            }
            normal = normal * side
            let t = CGFloat(i - range.lowerBound) / CGFloat(range.count - 1)
            shifted.append(points[i] + normal * (radii[i] * inset))
            widths.append(max(radii[i] * width * sin(CGFloat.pi * t), minimumWidth) * widthScale)
        }
        return ribbon(shifted, widths)
    }

    /// The outline of a curve with a radius at every point: one side forward, the other back.
    /// - Parameter firstNormal: when set, the first end is cut along this unit vector instead
    ///   of square to the curve, so a strand that meets a surface ends flat on it.
    static func ribbon(
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

    /// Shoelace area; ribbons built by `ribbon` are negative. Every filled shape must wind the
    /// same way: under the nonzero rule one wound the other way punches a hole where it overlaps.
    static func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }
}

func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

extension CGPoint {
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
