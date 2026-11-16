import CoreGraphics
import Testing
@testable import SymbiodockCore

struct PlayerVolumeTests {
    private func info(_ bundle: String?) -> NowPlayingInfo {
        NowPlayingInfo(
            title: "T", artist: "A", isPlaying: true, sourceName: "X", sourceBundleIdentifier: bundle)
    }

    @Test func onlyMusicAndSpotifyHaveAVolumeOfTheirOwn() {
        #expect(VolumeTarget.target(for: info("com.apple.Music")) == .appleMusic)
        #expect(VolumeTarget.target(for: info("com.spotify.client")) == .spotify)
        #expect(VolumeTarget.target(for: info("com.google.Chrome")) == nil)
        #expect(VolumeTarget.target(for: info("com.apple.Safari")) == nil)
        #expect(VolumeTarget.target(for: info(nil)) == nil)
    }

    @Test func percentIsClampedAndRounded() {
        #expect(VolumeLevel.percent(0.456) == 46)
        #expect(VolumeLevel.percent(-1) == 0)
        #expect(VolumeLevel.percent(7) == 100)
        #expect(VolumeLevel.percent(.nan) == 0)
        #expect(VolumeLevel.fraction(percent: 50) == 0.5)
        #expect(VolumeLevel.fraction(percent: 140) == 1)
        #expect(VolumeLevel.fraction(percent: -3) == 0)
    }

    @Test func theTopOfTheTrackIsFullVolume() {
        #expect(VolumeLevel.fraction(atY: 0, height: 80) == 1)
        #expect(VolumeLevel.fraction(atY: 80, height: 80) == 0)
        #expect(VolumeLevel.fraction(atY: 20, height: 80) == 0.75)
        // Dragged past either end.
        #expect(VolumeLevel.fraction(atY: -30, height: 80) == 1)
        #expect(VolumeLevel.fraction(atY: 200, height: 80) == 0)
        #expect(VolumeLevel.fraction(atY: 10, height: 0) == 0)
    }

    @MainActor @Test func theStateRemembersAVolumePerPlayer() {
        let state = IslandState()
        #expect(state.volumes.isEmpty)
        state.setVolume(0.4, for: .appleMusic)
        state.setVolume(1.7, for: .spotify)
        #expect(state.volumes == [.appleMusic: 0.4, .spotify: 1])
        // A player that cannot be asked has no slider.
        state.setVolume(nil, for: .appleMusic)
        #expect(state.volumes == [.spotify: 1])
    }
}
