import Foundation

/// One side of the display.
public enum ScreenEdge: String, Codable, Sendable, CaseIterable { case top, bottom, left, right }

/// One corner of the display.
public enum ScreenCorner: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Where the island rests: on the notch, along a screen edge, or in a screen corner.
public enum IslandAnchor: Equatable, Codable, Sendable {
    case notch
    /// `fraction` is 0...1 along the edge, from the left or from the top.
    case edge(ScreenEdge, fraction: Double)
    case corner(ScreenCorner)
}

/// Turns an anchor into bytes for persistence and back, never failing.
public enum AnchorCodec {
    /// Encodes an anchor as JSON.
    public static func encode(_ anchor: IslandAnchor) -> Data {
        (try? JSONEncoder().encode(anchor)) ?? Data()
    }

    /// Anything that cannot be decoded is `.notch`; an edge fraction is clamped to 0...1.
    public static func decode(_ data: Data?) -> IslandAnchor {
        guard let data, let anchor = try? JSONDecoder().decode(IslandAnchor.self, from: data)
        else { return .notch }
        if case .edge(let edge, let fraction) = anchor {
            return .edge(edge, fraction: fraction.isNaN ? 0 : min(max(fraction, 0), 1))
        }
        return anchor
    }
}
