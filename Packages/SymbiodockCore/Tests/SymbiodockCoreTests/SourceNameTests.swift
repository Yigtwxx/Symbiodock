import Testing
@testable import SymbiodockCore

struct SourceNameTests {
    @Test func knownAppsGetTheirName() {
        #expect(SourceName.displayName(forBundleIdentifier: "com.apple.Music") == "Music")
        #expect(SourceName.displayName(forBundleIdentifier: "com.spotify.client") == "Spotify")
        #expect(SourceName.displayName(forBundleIdentifier: "com.apple.Safari") == "Safari")
    }

    @Test func unknownAppsUseTheLastIdentifierComponent() {
        #expect(SourceName.displayName(forBundleIdentifier: "org.videolan.vlc") == "Vlc")
        #expect(SourceName.displayName(forBundleIdentifier: "") == "Unknown")
    }
}
