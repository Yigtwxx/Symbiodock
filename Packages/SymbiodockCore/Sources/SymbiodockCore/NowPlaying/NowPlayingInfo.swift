import Foundation

/// What is playing right now, independent of where the information came from.
public struct NowPlayingInfo: Equatable, Sendable {
    /// Longer "durations" are sentinels (live streams report about 9.2e12 seconds).
    public static let maximumPlausibleDuration: TimeInterval = 1_000_000

    public var title: String
    public var artist: String
    public var album: String?
    public var artworkData: Data?
    public var duration: TimeInterval?
    /// Playback position at `elapsedAt`.
    public var elapsed: TimeInterval?
    /// When `elapsed` was measured; nil if the source did not say.
    public var elapsedAt: Date?
    public var isPlaying: Bool
    /// "Music", "Spotify", "Safari", ...
    public var sourceName: String

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        artworkData: Data? = nil,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        elapsedAt: Date? = nil,
        isPlaying: Bool,
        sourceName: String
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.duration = duration
        self.elapsed = elapsed
        self.elapsedAt = elapsedAt
        self.isPlaying = isPlaying
        self.sourceName = sourceName
    }
}

public enum PlaybackCommand: Equatable, Sendable {
    case togglePlayPause
    case next
    case previous
}

public protocol NowPlayingProvider: Sendable {
    /// False when the provider cannot work on this system.
    func isAvailable() async -> Bool
    /// Emits the current track, or nil when nothing is playing.
    /// The stream finishing means the provider has failed for good.
    var updates: AsyncStream<NowPlayingInfo?> { get }
    func send(_ command: PlaybackCommand) async
}
