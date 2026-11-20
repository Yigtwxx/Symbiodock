import CoreGraphics
import Foundation

/// Where the light that greets a new track plays.
public enum TrackGlowSurface: Equatable, Sendable {
    /// Along the collapsed island's rim.
    case island
    /// Round the bubble left of the island.
    case bubble
}

/// The light that greets a new track, while it plays.
public struct TrackGlow: Equatable, Sendable {
    /// Goes up with every light, so that each one is a new view and plays once.
    public let serial: Int
    public let surface: TrackGlowSurface
    /// Whose track it greets: its cover gives the colours.
    public let source: NowPlayingSource
}

/// A track that has just changed and waits for its cover before its light plays.
public struct AwaitedTrackGlow: Equatable, Sendable {
    public let serial: Int
    public let source: NowPlayingSource
    let staleArtwork: Data?
    /// The shortest wait is over: the light plays as soon as the new cover is there.
    var isSettled = false
}

/// How the light moves: a line drawn from the middle of the rim out to both ends, lit whole
/// for a moment, then fading.
public enum TrackGlowMotion {
    /// The light never plays sooner after the change than this: the wings settle, and quick
    /// skips become one.
    public static let minimumWait: TimeInterval = 0.4
    /// After this long the light plays with whatever cover there is.
    public static let maximumWait: TimeInterval = 1.0

    public static let spread: TimeInterval = 0.6
    public static let hold: TimeInterval = 0.3
    public static let fade: TimeInterval = 0.6
    public static let duration: TimeInterval = spread + hold + fade

    /// How long the whole line takes to appear when it does not spread (Reduce Motion).
    static let stillRise: TimeInterval = 0.3

    /// How much of each half of the line is drawn `time` seconds in: 0 at the middle, 1 at
    /// the ends. It slows as it arrives.
    public static func reach(at time: TimeInterval) -> Double {
        let progress = min(max(time / spread, 0), 1)
        return 1 - pow(1 - progress, 3)
    }

    /// The light's strength `time` seconds in: full until the hold ends, then falling to
    /// nothing; nothing before it starts and after it is over.
    public static func opacity(at time: TimeInterval) -> Double {
        guard time >= 0, time < duration else { return 0 }
        let fading = (time - spread - hold) / fade
        guard fading > 0 else { return 1 }
        return pow(1 - fading, 2)
    }

    /// The same without the spread: the whole line rises, holds and fades over the same time.
    public static func stillOpacity(at time: TimeInterval) -> Double {
        guard time >= 0, time < duration else { return 0 }
        return min(time / stillRise, 1) * opacity(at: time)
    }
}

/// The line the light is drawn along, as an open path whose middle is where the light starts.
/// The origin is the top left and y runs down, as on screen.
public enum TrackGlowOutline {
    /// The island's rim where it is free of the screen: from the end of one docked edge round
    /// to the start of the next. At the notch that is down the right side, under the notch and
    /// up the left side, so its middle is under the middle of the notch.
    public static func island(
        in rect: CGRect, radii: IslandCornerRadii, dockedEdges: Set<ScreenEdge>
    ) -> CGPath {
        let half = min(rect.width, rect.height) / 2
        // Clockwise as seen on screen, from the top left: edge `i` runs from corner `i` to
        // the next one.
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        let rounding = [radii.topLeading, radii.topTrailing, radii.bottomTrailing, radii.bottomLeading]
            .map { min(max($0, 0), half) }
        let edges: [ScreenEdge] = [.top, .right, .bottom, .left]
        let isFree = edges.map { !dockedEdges.contains($0) }
        let path = CGMutablePath()
        guard isFree.contains(true) else { return path }
        // The line begins with the first free edge after a docked one.
        let start = (0..<4).first { isFree[$0] && !isFree[($0 + 3) % 4] } ?? 0
        let count = (0..<4).prefix { isFree[(start + $0) % 4] }.count
        let isClosed = count == 4

        func point(from a: CGPoint, toward b: CGPoint, by distance: CGFloat) -> CGPoint {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { return a }
            return CGPoint(
                x: a.x + (b.x - a.x) * distance / length, y: a.y + (b.y - a.y) * distance / length)
        }

        path.move(to: point(from: corners[start], toward: corners[(start + 1) % 4], by: rounding[start]))
        for step in 0..<count {
            let edge = (start + step) % 4
            let corner = (edge + 1) % 4
            if step == count - 1, !isClosed {
                // The last free edge ends where the docked one begins.
                path.addLine(to: point(from: corners[corner], toward: corners[edge], by: rounding[corner]))
            } else if rounding[corner] > 0 {
                path.addArc(
                    tangent1End: corners[corner], tangent2End: corners[(corner + 1) % 4],
                    radius: rounding[corner])
            } else {
                path.addLine(to: corners[corner])
            }
        }
        if isClosed { path.closeSubpath() }
        return path
    }

    /// The bubble's rim: a circle that begins and ends at the bottom, so its middle is the top
    /// and the two arms of the light meet below.
    public static func bubble(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        // With y running down, a quarter turn is straight down.
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
            startAngle: .pi / 2, endAngle: .pi / 2 + 2 * .pi, clockwise: false)
        return path
    }
}
