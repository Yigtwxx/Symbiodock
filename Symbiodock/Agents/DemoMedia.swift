#if DEBUG
import Foundation
import SymbiodockCore

/// A fixed playing track for looking at (and measuring) the media face without real music:
/// `open --env SYMBIODOCK_DEMO_MEDIA=1 build/Build/Products/Debug/Symbiodock.app`.
/// The real now-playing coordinator is not started. It may be combined with
/// `SYMBIODOCK_DEMO_AGENTS`.
@MainActor
enum DemoMedia {
    static var requested: Bool {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_MEDIA"] == "1"
    }

    static func apply(to state: IslandState) {
        state.setNowPlaying(
            NowPlayingInfo(title: "Demo track", artist: "Demo", isPlaying: true, sourceName: "Music"))
    }
}
#endif
