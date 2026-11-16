/// Where a slot's information comes from, and so where its commands go.
public enum NowPlayingOrigin: Equatable, Hashable, Sendable {
    /// The system-wide source: whatever the system calls "now playing".
    case system
    /// A player that is asked directly, next to the system-wide source (Apple Music).
    case companion
    /// A playing app the system knows about but does not currently elect.
    case client(pid: Int32)
}

/// An app the system knows plays something, whether or not it is the one it elects.
public struct NowPlayingClient: Equatable, Sendable {
    public var pid: Int32
    public var isElected: Bool
    public var info: NowPlayingInfo

    public init(pid: Int32, isElected: Bool, info: NowPlayingInfo) {
        self.pid = pid
        self.isElected = isElected
        self.info = info
    }
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

/// Decides what the island shows when more than one source reports at the same time.
///
/// The system elects one source (`system`). Apple Music is also asked directly (`companion`),
/// and the system lists the other apps that play (`others`). The first slot is the island's
/// main track; a second slot peeks out behind it.
public enum NowPlayingLineup {
    static let maximumSlots = 2

    public static func slots(
        system: NowPlayingInfo?, companion: NowPlayingInfo?, others: [NowPlayingClient] = []
    ) -> [NowPlayingSlot] {
        var slots: [NowPlayingSlot] = []
        if let system { slots.append(NowPlayingSlot(info: system, origin: .system)) }
        // The system is already talking about the companion's player: one source, not two.
        if let companion, !slots.contains(where: { isSameSource($0.info, companion) }) {
            slots.append(NowPlayingSlot(info: companion, origin: .companion))
        }
        // The companion comes first: Music is commanded over AppleScript, which is known to
        // work. An app is not heard while paused, and the elected one is `system` already.
        for other in others where slots.count < maximumSlots {
            guard other.info.isPlaying, !other.isElected,
                  !slots.contains(where: { isSameSource($0.info, other.info) })
            else { continue }
            slots.append(NowPlayingSlot(info: other.info, origin: .client(pid: other.pid)))
        }
        // What is heard goes in front; a paused track must not hide a playing one.
        if slots.count == 2, !slots[0].info.isPlaying, slots[1].info.isPlaying {
            slots.swapAt(0, 1)
        }
        return slots
    }

    static func isSameSource(_ a: NowPlayingInfo, _ b: NowPlayingInfo) -> Bool {
        if let left = a.sourceBundleIdentifier, let right = b.sourceBundleIdentifier {
            return left == right
        }
        return a.sourceName == b.sourceName
    }
}
