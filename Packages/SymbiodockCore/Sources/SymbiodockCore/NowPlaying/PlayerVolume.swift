import CoreGraphics

/// A player whose own volume can be set, apart from the system's. Only these get a volume
/// slider: a browser tab has no volume of its own that can be reached.
public enum VolumeTarget: String, CaseIterable, Hashable, Sendable {
    case appleMusic
    case spotify

    public var bundleIdentifier: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// The name the player answers to in an Apple Event, and the one read out.
    public var applicationName: String {
        switch self {
        case .appleMusic: "Music"
        case .spotify: "Spotify"
        }
    }

    /// The player behind a track, if its volume can be set.
    public static func target(for info: NowPlayingInfo) -> VolumeTarget? {
        allCases.first { $0.bundleIdentifier == info.sourceBundleIdentifier }
    }
}

/// What the volume slider asks for.
public enum VolumeRequest: Equatable, Sendable {
    /// Ask the player how loud it is.
    case read(VolumeTarget)
    /// Set the player's volume, 0...1.
    case set(VolumeTarget, Double)
}

/// A player's volume as a fraction 0...1, and as the 0...100 the players speak.
public enum VolumeLevel {
    public static func percent(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    public static func fraction(percent: Int) -> Double {
        Double(min(max(percent, 0), 100)) / 100
    }

    /// The level under the pointer on a vertical track: full at the top, silent at the bottom.
    public static func fraction(atY y: CGFloat, height: CGFloat) -> Double {
        guard height > 0, y.isFinite else { return 0 }
        return Double(min(max(1 - y / height, 0), 1))
    }
}
