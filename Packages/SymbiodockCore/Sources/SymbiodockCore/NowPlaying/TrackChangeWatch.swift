import Foundation

/// Which player a track comes from, however the island heard of it.
public struct NowPlayingSource: Hashable, Sendable {
    public let key: String

    public init(_ info: NowPlayingInfo) {
        key = info.sourceBundleIdentifier ?? info.sourceName
    }
}

/// A track that has just begun on one source.
public struct TrackChange: Equatable, Sendable {
    public let source: NowPlayingSource
    /// The cover the source showed for the track before. The new cover often arrives a moment
    /// after the new title, so a cover equal to this one is not yet the new track's.
    public let staleArtwork: Data?

    public init(source: NowPlayingSource, staleArtwork: Data?) {
        self.source = source
        self.staleArtwork = staleArtwork
    }
}

/// Notices when what a source plays becomes another track.
///
/// A track is its title and artist. Only a track heard playing counts: pausing and resuming
/// changes nothing, and a track skipped to while paused is new once it plays. Each source is
/// remembered for as long as the app runs, so a source that leaves the island and returns
/// with the same track is not new either.
public struct TrackChangeWatch: Sendable {
    private struct Track: Equatable, Sendable {
        let title: String
        let artist: String
    }

    private var lastPlayed: [NowPlayingSource: Track] = [:]
    private var lastArtwork: [NowPlayingSource: Data] = [:]

    public init() {}

    /// Takes what the island shows now and returns the sources whose track is new, in the
    /// order of the slots.
    public mutating func update(_ slots: [NowPlayingSlot]) -> [TrackChange] {
        var changes: [TrackChange] = []
        for slot in slots {
            let info = slot.info
            guard !info.title.isEmpty else { continue }
            let source = NowPlayingSource(info)
            let track = Track(title: info.title, artist: info.artist)
            if info.isPlaying, lastPlayed[source] != track {
                changes.append(TrackChange(source: source, staleArtwork: lastArtwork[source]))
                lastPlayed[source] = track
            }
            // The cover shown with the track last heard is what a later track has to replace.
            if lastPlayed[source] == track { lastArtwork[source] = info.artworkData }
        }
        return changes
    }
}
