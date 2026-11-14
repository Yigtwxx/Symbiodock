import Foundation

/// One side of the display.
public enum ScreenEdge: String, Codable, Sendable, CaseIterable { case top, bottom, left, right }

/// One corner of the display.
public enum ScreenCorner: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Where the island rests: on the notch, along a screen edge, or in a screen corner.
public enum IslandAnchor: Equatable, Codable, Sendable {
    /// Hanging from the notch.
    case notch
    /// Floating along one screen edge. `fraction` is where the island's center sits along that
    /// edge of the visible frame, 0...1, from the left or from the top.
    case edge(ScreenEdge, fraction: Double)
    /// Pinned in one corner of the visible frame.
    case corner(ScreenCorner)
}

/// Turns an anchor into bytes for persistence and back, never failing.
public enum AnchorCodec {
    /// Encodes an anchor as JSON. A non-finite edge fraction is stored as 0.5 (JSON cannot hold it).
    public static func encode(_ anchor: IslandAnchor) -> Data {
        var anchor = anchor
        if case .edge(let edge, let fraction) = anchor, !fraction.isFinite {
            anchor = .edge(edge, fraction: 0.5)
        }
        // Sorted keys: dictionary order is random per process and would change the bytes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(anchor)) ?? Data()
    }

    /// Anything that cannot be decoded is `.notch`; an edge fraction is clamped to 0...1.
    public static func decode(_ data: Data?) -> IslandAnchor {
        guard let data, let anchor = try? JSONDecoder().decode(IslandAnchor.self, from: data)
        else { return .notch }
        if case .edge(let edge, let fraction) = anchor {
            return .edge(edge, fraction: min(max(fraction, 0), 1))
        }
        return anchor
    }
}
