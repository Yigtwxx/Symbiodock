/// Where a slot's information comes from, and so where its commands go.
public enum NowPlayingOrigin: Equatable, Hashable, Sendable {
    /// The system-wide source: whatever the system calls "now playing".
    case system
    /// A player that is asked directly, next to the system-wide source (Apple Music).
    case companion
}

/// One thing that plays, and who to tell when its buttons are pressed.
public struct NowPlayingSlot: Equatable, Sendable, Identifiable {
    public var info: NowPlayingInfo
    public var origin: NowPlayingOrigin

    public var id: NowPlayingOrigin { origin }

    public init(info: NowPlayingInfo, origin: NowPlayingOrigin) {
        self.info = info
        self.origin = origin
    }
}

/// Decides what the island shows when two sources report at the same time.
///
/// The system names one source only, so the second one can only be a player that is asked
/// directly. The first slot is the island's main track; a second slot peeks out behind it.
public enum NowPlayingLineup {
    public static func slots(
        system: NowPlayingInfo?, companion: NowPlayingInfo?
    ) -> [NowPlayingSlot] {
        guard let system else {
            return companion.map { [NowPlayingSlot(info: $0, origin: .companion)] } ?? []
        }
        let first = NowPlayingSlot(info: system, origin: .system)
        // The system is already talking about the companion's player: one source, not two.
        guard let companion, !isSameSource(system, companion) else { return [first] }
        let second = NowPlayingSlot(info: companion, origin: .companion)
        // What is heard goes in front; a paused track must not hide a playing one.
        return !system.isPlaying && companion.isPlaying ? [second, first] : [first, second]
    }

    static func isSameSource(_ a: NowPlayingInfo, _ b: NowPlayingInfo) -> Bool {
        if let left = a.sourceBundleIdentifier, let right = b.sourceBundleIdentifier {
            return left == right
        }
        return a.sourceName == b.sourceName
    }
}
