import CoreGraphics
import Foundation

/// The light of a working agent: colours that flow just outside the collapsed island, along
/// its long edge that is free of the screen, as a fine line and a glow that breathes.
/// Measures and motion only, as pure functions; the app draws them.
public enum WorkingAurora {
    /// Seconds the colours take to travel one whole run along the edge.
    public static let flowPeriod: TimeInterval = 3.2
    /// Seconds for one breath of the glow, out and back.
    public static let breathPeriod: TimeInterval = 2.4
    /// Seconds the light takes to appear and to go.
    public static let fade: TimeInterval = 0.35

    /// When, after a finish seal begins, the light starts to turn mint, and how long the turn
    /// takes: the moments the seal's own frame turns mint (`AgentSealTiming.pose(at:).mint`).
    public static var finishTintDelay: TimeInterval { AgentSealTiming.rounded }
    public static var finishTintDuration: TimeInterval { (AgentSealTiming.checked - AgentSealTiming.rounded) / 2 }
    /// Seconds the light takes to return to a tool's colours when work goes on after a finish.
    public static let tintBack: TimeInterval = 0.3

    /// How mint the light is `time` seconds into a finish seal: 0 the tool's colours, 1 mint.
    public static func finishTint(at time: TimeInterval) -> Double {
        AgentSealTiming.pose(at: time).mint
    }

    /// How far the glow reaches out from the edge at a stretch of 1, in points.
    public static let reach: CGFloat = 9
    public static let lineWidth: CGFloat = 1
    /// How far inside each end of the edge the line begins: clear of the rounded corners.
    public static let lineInset: CGFloat = 9
    /// How far inside each end of the edge the glow begins.
    public static let glowInset: CGFloat = 8
    /// The length at each end over which the line and the glow fade in.
    public static let endFade: CGFloat = 14

    /// The glow's strength at the low point of its breath; at the high point it is 1.
    public static let dimmestGlow = 0.6
    /// How far the glow reaches at the low and at the high point of its breath, as a share
    /// of `reach`.
    public static let shortestStretch = 0.75
    public static let longestStretch = 1.3
    /// The glow's strength when nothing moves (Reduce Motion), at a stretch of 1.
    public static let stillGlow = 0.8

    /// How deep the band beside the edge is: room for the glow at its longest.
    public static var depth: CGFloat { reach * CGFloat(longestStretch) }

    /// The edge of the island the light plays along: its long edge that does not lie
    /// against the screen. A vertical strip is long on its sides, anything else on its top
    /// and bottom.
    public static func edge(dockedEdges: Set<ScreenEdge>, isVertical: Bool) -> ScreenEdge {
        if isVertical { return dockedEdges.contains(.left) ? .right : .left }
        return dockedEdges.contains(.bottom) ? .top : .bottom
    }

    /// The band the light is drawn in: against `edge` of `island`, outside it, as long as
    /// the edge and `depth` deep. Same coordinates as `island` (y runs down).
    public static func band(island: CGRect, edge: ScreenEdge) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: island.minX, y: island.maxY, width: island.width, height: depth)
        case .top: CGRect(x: island.minX, y: island.minY - depth, width: island.width, height: depth)
        case .left: CGRect(x: island.minX - depth, y: island.minY, width: depth, height: island.height)
        case .right: CGRect(x: island.maxX, y: island.minY, width: depth, height: island.height)
        }
    }

    /// The glow as drawn: x along the edge from 0 to `length`, y out from the edge starting
    /// at 0. It begins `glowInset` inside each end and reaches `reach` times `stretch`.
    public static func glowRect(length: CGFloat, stretch: Double) -> CGRect {
        CGRect(x: glowInset, y: 0, width: max(length - 2 * glowInset, 0), height: reach * CGFloat(stretch))
    }

    /// The fine line as drawn, in the same coordinates as `glowRect`: `lineInset` inside each
    /// end and `lineWidth` thick.
    public static func lineRect(length: CGFloat) -> CGRect {
        CGRect(x: lineInset, y: 0, width: max(length - 2 * lineInset, 0), height: lineWidth)
    }

    /// Where the line and the glow fade in at their ends, for a piece `length` long:
    /// gradient locations for clear, full, full, clear. A piece shorter than twice
    /// `endFade` (or with no length) fades over half of itself at each end.
    public static func endLocations(length: CGFloat) -> [Double] {
        let fade = length > 0 ? min(Double(endFade / length), 0.5) : 0.5
        return [0, fade, 1 - fade, 1]
    }

    /// How strong the glow is on its way out from the edge: `place` runs 0 at the edge to 1
    /// at the end of its reach.
    public static let falloff: [(place: Double, strength: Double)] = [(0, 1), (0.3, 0.5), (0.65, 0.15), (1, 0)]

    /// How far through its breath the glow is at `time`: 0 at its dimmest and shortest, 1 at
    /// its brightest and longest, easing in and out.
    public static func breath(at time: TimeInterval) -> Double {
        0.5 - 0.5 * cos(2 * .pi * time / breathPeriod)
    }

    /// The glow's strength at `time`, `dimmestGlow`...1.
    public static func glowOpacity(at time: TimeInterval) -> Double {
        dimmestGlow + (1 - dimmestGlow) * breath(at: time)
    }

    /// How far the glow reaches at `time`, as a share of `reach`.
    public static func stretch(at time: TimeInterval) -> Double {
        shortestStretch + (longestStretch - shortestStretch) * breath(at: time)
    }

    /// How far the colours have travelled along the edge at `time`: a share of one run, 0..<1.
    public static func flow(at time: TimeInterval) -> Double {
        let turn = (time / flowPeriod).truncatingRemainder(dividingBy: 1)
        return turn < 0 ? turn + 1 : turn
    }
}
