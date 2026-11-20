#if DEBUG
import Foundation
import SymbiodockCore

/// A fixed playing track for looking at (and measuring) the media face without real music:
/// `open --env SYMBIODOCK_DEMO_MEDIA=1 build/Build/Products/Debug/Symbiodock.app`.
/// `SYMBIODOCK_DEMO_MEDIA=2` adds a second source that plays at the same time.
/// `SYMBIODOCK_DEMO_MEDIA=3` is the case two sources were lost in: Music is the app the system
/// elects (so system and companion agree), and a browser plays as one of the other apps.
/// The real now-playing coordinator is not started. It may be combined with
/// `SYMBIODOCK_DEMO_AGENTS`.
@MainActor
enum DemoMedia {
    static var requested: Bool {
        ["1", "2", "3"].contains(ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_MEDIA"])
    }

    static var wantsTwoSources: Bool {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_MEDIA"] == "2"
    }

    static var wantsOtherApp: Bool {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_MEDIA"] == "3"
    }

    static func apply(
        to state: IslandState, twoSources: Bool = wantsTwoSources, otherApp: Bool = wantsOtherApp
    ) {
        state.setVolume(0.6, for: .appleMusic)
        if otherApp {
            let track = NowPlayingInfo(
                title: "Demo track", artist: "Demo", duration: 200, elapsed: 60, elapsedAt: Date(),
                isPlaying: true, sourceName: "Music", sourceBundleIdentifier: "com.apple.Music")
            state.setNowPlaying(track)
            state.setCompanionPlaying(track)
            state.setOtherPlaying([
                NowPlayingClient(pid: 2, isElected: true, info: track),
                NowPlayingClient(
                    pid: 1, isElected: false,
                    info: NowPlayingInfo(
                        title: "Demo stream", artist: "", isPlaying: true, sourceName: "Safari",
                        sourceBundleIdentifier: "com.apple.Safari", site: .kick)),
            ])
            return
        }
        guard twoSources else {
            state.setNowPlaying(
                NowPlayingInfo(
                    title: "Demo track", artist: "Demo", duration: 226, elapsed: 93,
                    elapsedAt: Date(), isPlaying: true, sourceName: "Music",
                    sourceBundleIdentifier: "com.apple.Music"))
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
