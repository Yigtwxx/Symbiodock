import CoreGraphics
import Foundation
import Testing
@testable import SymbiodockCore

struct TrackGlowTests {
    @Test func theLineReachesItsEndsAsTheSpreadEnds() {
        #expect(TrackGlowMotion.reach(at: -1) == 0)
        #expect(TrackGlowMotion.reach(at: 0) == 0)
        #expect(TrackGlowMotion.reach(at: TrackGlowMotion.spread) == 1)
        #expect(TrackGlowMotion.reach(at: 5) == 1)
    }

    @Test func theSpreadSlowsAsItArrives() {
        let half = TrackGlowMotion.reach(at: TrackGlowMotion.spread / 2)
        #expect(half > 0.8 && half < 1)
        var last = 0.0
        for step in 1...20 {
            let reach = TrackGlowMotion.reach(at: TrackGlowMotion.spread * Double(step) / 20)
            #expect(reach >= last)
            last = reach
        }
    }

    @Test func theLightHoldsThenFadesToNothing() {
        #expect(abs(TrackGlowMotion.duration - 1.5) < 1e-9)
        #expect(TrackGlowMotion.opacity(at: -0.1) == 0)
        #expect(TrackGlowMotion.opacity(at: 0) == 1)
        #expect(TrackGlowMotion.opacity(at: 0.89) == 1)
        let fading = TrackGlowMotion.opacity(at: 1.2)
        #expect(fading > 0 && fading < 1)
        #expect(TrackGlowMotion.opacity(at: TrackGlowMotion.duration) == 0)
        #expect(TrackGlowMotion.opacity(at: 3) == 0)
    }

    @Test func withoutMotionTheLightRisesHoldsAndFades() {
        #expect(TrackGlowMotion.stillOpacity(at: 0) == 0)
        #expect(abs(TrackGlowMotion.stillOpacity(at: 0.15) - 0.5) < 1e-9)
        #expect(TrackGlowMotion.stillOpacity(at: 0.5) == 1)
        #expect(TrackGlowMotion.stillOpacity(at: 1.2) == TrackGlowMotion.opacity(at: 1.2))
        #expect(TrackGlowMotion.stillOpacity(at: TrackGlowMotion.duration) == 0)
    }

    @Test func theWaitForTheCoverIsBounded() {
        #expect(TrackGlowMotion.minimumWait == 0.4)
        #expect(TrackGlowMotion.maximumWait == 1.0)
    }

    // MARK: Outline

    /// The corners of the line once its curves are made of short straight pieces.
    private func points(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.flattened(threshold: 0.01).applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            case .closeSubpath: if let first = points.first { points.append(first) }
            default: break
            }
        }
        return points
    }

    /// The point half way along the line.
    private func middle(of path: CGPath) -> CGPoint {
        let points = points(of: path)
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = lengths.reduce(0, +) / 2
        for (index, length) in lengths.enumerated() {
            if left <= length, length > 0 {
                let (a, b) = (points[index], points[index + 1])
                return CGPoint(x: a.x + (b.x - a.x) * left / length, y: a.y + (b.y - a.y) * left / length)
            }
            left -= length
        }
        return points.last ?? .zero
    }

    private func isClose(_ a: CGPoint, _ b: CGPoint) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 0.05
    }

    private func fills(_ path: CGPath, _ rect: CGRect) -> Bool {
        let box = path.boundingBoxOfPath
        return isClose(box.origin, rect.origin)
            && isClose(CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
    }

    private func outline(_ anchor: IslandAnchor, _ size: CGSize) -> CGPath {
        TrackGlowOutline.island(
            in: CGRect(origin: .zero, size: size),
            radii: IslandLayout.cornerRadii(anchor: anchor, radius: 10),
            dockedEdges: IslandLayout.dockedEdges(anchor: anchor))
    }

    @Test func atTheNotchTheLineStartsUnderTheMiddle() {
        let path = outline(.notch, CGSize(width: 272, height: 34))
        let points = points(of: path)
        #expect(isClose(points.first ?? .zero, CGPoint(x: 272, y: 0)))
        #expect(isClose(points.last ?? .zero, CGPoint(x: 0, y: 0)))
        #expect(isClose(middle(of: path), CGPoint(x: 136, y: 34)))
        #expect(fills(path, CGRect(x: 0, y: 0, width: 272, height: 34)))
    }

    @Test func onAStripTheLineStartsAtTheMiddleOfTheFreeLongEdge() {
        let right = outline(.edge(.right, fraction: 0.5), CGSize(width: 36, height: 170))
        #expect(isClose(middle(of: right), CGPoint(x: 0, y: 85)))
        #expect(isClose(points(of: right).first ?? .zero, CGPoint(x: 36, y: 170)))
        #expect(isClose(points(of: right).last ?? .zero, CGPoint(x: 36, y: 0)))
        let left = outline(.edge(.left, fraction: 0.5), CGSize(width: 36, height: 170))
        #expect(isClose(middle(of: left), CGPoint(x: 36, y: 85)))
    }

    @Test func onACapsuleTheLineStartsAtTheMiddleOfTheFreeLongEdge() {
        let bottom = outline(.edge(.bottom, fraction: 0.5), CGSize(width: 200, height: 36))
        #expect(isClose(middle(of: bottom), CGPoint(x: 100, y: 0)))
        let top = outline(.edge(.top, fraction: 0.5), CGSize(width: 200, height: 36))
        #expect(isClose(middle(of: top), CGPoint(x: 100, y: 36)))
    }

    @Test func inACornerTheLineRunsAlongTheTwoFreeEdges() {
        let path = outline(.corner(.topLeft), CGSize(width: 200, height: 36))
        let points = points(of: path)
        #expect(isClose(points.first ?? .zero, CGPoint(x: 200, y: 0)))
        #expect(isClose(points.last ?? .zero, CGPoint(x: 0, y: 36)))
        // Half way along a line that is mostly the bottom edge.
        #expect(abs(middle(of: path).y - 36) < 0.05)
    }

    @Test func aRadiusLargerThanTheIslandIsCutDown() {
        let path = TrackGlowOutline.island(
            in: CGRect(x: 0, y: 0, width: 40, height: 20),
            radii: IslandCornerRadii(topLeading: 0, topTrailing: 0, bottomLeading: 50, bottomTrailing: 50),
            dockedEdges: [.top])
        #expect(fills(path, CGRect(x: 0, y: 0, width: 40, height: 20)))
    }

    @Test func roundTheBubbleTheLineStartsAtTheTop() {
        let path = TrackGlowOutline.bubble(in: CGRect(x: 0, y: 0, width: 28, height: 28))
        let points = points(of: path)
        #expect(isClose(points.first ?? .zero, CGPoint(x: 14, y: 28)))
        #expect(isClose(points.last ?? .zero, CGPoint(x: 14, y: 28)))
        #expect(isClose(middle(of: path), CGPoint(x: 14, y: 0)))
    }
}
