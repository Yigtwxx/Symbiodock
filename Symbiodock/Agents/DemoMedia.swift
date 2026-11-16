#if DEBUG
import Foundation
import SymbiodockCore

/// A fixed playing track for looking at (and measuring) the media face without real music:
/// `open --env SYMBIODOCK_DEMO_MEDIA=1 build/Build/Products/Debug/Symbiodock.app`.
/// `SYMBIODOCK_DEMO_MEDIA=2` adds a second source that plays at the same time.
/// The real now-playing coordinator is not started. It may be combined with
/// `SYMBIODOCK_DEMO_AGENTS`.
@MainActor
enum DemoMedia {
    static var requested: Bool {
        ["1", "2"].contains(ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_MEDIA"])
    }

    static var wantsTwoSources: Bool {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_MEDIA"] == "2"
    }

    static func apply(to state: IslandState, twoSources: Bool = wantsTwoSources) {
        guard twoSources else {
            state.setNowPlaying(
                NowPlayingInfo(
                    title: "Demo track", artist: "Demo", isPlaying: true, sourceName: "Music"))
            return
        }
        state.setNowPlaying(
            NowPlayingInfo(
                title: "Demo stream", artist: "", isPlaying: true, sourceName: "Chrome",
                sourceBundleIdentifier: "com.google.Chrome"))
        state.setCompanionPlaying(
            NowPlayingInfo(
                title: "Demo track", artist: "Demo", duration: 200, elapsed: 60, elapsedAt: Date(),
                isPlaying: true, sourceName: "Music", sourceBundleIdentifier: "com.apple.Music"))
    }
}
#endif
