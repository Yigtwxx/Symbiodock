#if DEBUG
import AppKit
import Foundation
import SymbiodockCore

/// A fixed playing track for looking at (and measuring) the media face without real music:
/// `open --env SYMBIODOCK_DEMO_MEDIA=1 build/Build/Products/Debug/Symbiodock.app`.
/// `SYMBIODOCK_DEMO_MEDIA=2` adds a second source that plays at the same time.
/// `SYMBIODOCK_DEMO_MEDIA=3` is the case two sources were lost in: Music is the app the system
/// elects (so system and companion agree), and a browser plays as one of the other apps.
/// The real now-playing coordinator is not started. It may be combined with
/// `SYMBIODOCK_DEMO_AGENTS`.
/// With `SYMBIODOCK_DEMO_TRACKS=1` as well (and `SYMBIODOCK_DEMO_MEDIA` 1 or 2), the Music track
/// changes every four seconds, each with another cover: for looking at the light that greets a
/// new track.
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

    static var cyclesTracks: Bool {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_TRACKS"] == "1" && !wantsOtherApp
    }

    /// Changes the Music track every four seconds for as long as the app runs.
    static func cycleTracks(on state: IslandState, twoSources: Bool = wantsTwoSources) {
        Task { @MainActor in
            let covers: [[Double]] = [[0.55, 0.7], [0.08], [0.3, 0.45, 0.6], [0, 0.9, 0.78]]
            var number = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                let track = NowPlayingInfo(
                    title: "Demo track \(number)", artist: "Demo",
                    artworkData: cover(covers[number % covers.count]), duration: 226, elapsed: 0,
                    elapsedAt: Date(), isPlaying: true, sourceName: "Music",
                    sourceBundleIdentifier: "com.apple.Music")
                if twoSources {
                    state.setCompanionPlaying(track)
                } else {
                    state.setNowPlaying(track)
                }
                number += 1
            }
        }
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
                    title: "Demo track", artist: "Demo", artworkData: cover([0, 0.9, 0.78]),
                    duration: 226, elapsed: 93,
                    elapsedAt: Date(), isPlaying: true, sourceName: "Music",
                    sourceBundleIdentifier: "com.apple.Music"))
            return
        }
        state.setNowPlaying(
            NowPlayingInfo(
                title: "Demo stream", artist: "", artworkData: cover([0.38]), isPlaying: true,
                sourceName: "Chrome", sourceBundleIdentifier: "com.google.Chrome"))
        state.setCompanionPlaying(
            NowPlayingInfo(
                title: "Demo track", artist: "Demo", artworkData: cover([0.08, 0.55]),
                duration: 200, elapsed: 60, elapsedAt: Date(),
                isPlaying: true, sourceName: "Music", sourceBundleIdentifier: "com.apple.Music"))
    }

    /// A cover that runs left to right through `hues` (0...1 round the wheel): something for
    /// the bars to take their colours from.
    static func cover(_ hues: [Double]) -> Data? {
        let side = 64
        let colors = hues.map { NSColor(hue: $0, saturation: 0.8, brightness: 0.85, alpha: 1) }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            if colors.count > 1 {
                NSGradient(colors: colors)?.draw(in: rect, angle: 0)
            } else {
                colors.first?.setFill()
                rect.fill()
            }
            return true
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
#endif
