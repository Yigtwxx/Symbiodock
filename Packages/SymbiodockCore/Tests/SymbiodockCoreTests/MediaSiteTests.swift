import Testing
@testable import SymbiodockCore

struct MediaSiteTests {
    @Test func hostDecidesTheSite() {
        #expect(MediaSite.site(forPageURL: "https://www.youtube.com/watch?v=abc") == .youtube)
        #expect(MediaSite.site(forPageURL: "https://music.youtube.com/watch?v=abc") == .youtube)
        #expect(MediaSite.site(forPageURL: "https://youtu.be/abc") == .youtube)
        #expect(MediaSite.site(forPageURL: "https://kick.com/lynxcerezlol") == .kick)
        #expect(MediaSite.site(forPageURL: "https://www.twitch.tv/riotgames") == .twitch)
        #expect(MediaSite.site(forPageURL: "https://WWW.YouTube.com/") == .youtube)
    }

    @Test func lookalikeAndUnknownHostsAreNotSites() {
        #expect(MediaSite.site(forPageURL: "https://notyoutube.com/watch") == nil)
        #expect(MediaSite.site(forPageURL: "https://example.com/?next=youtube.com") == nil)
        #expect(MediaSite.site(forPageURL: "https://open.spotify.com/track/1") == nil)
        #expect(MediaSite.site(forPageURL: "missing value") == nil)
        #expect(MediaSite.site(forPageURL: "") == nil)
    }

    @Test func aPageTitleEndingInTheSiteNameNamesTheSite() {
        #expect(MediaSite.site(inPageTitle: "LynxCerezLoL Live Stream | Kick") == .kick)
        #expect(MediaSite.site(inPageTitle: "Some Video - YouTube") == .youtube)
        #expect(MediaSite.site(inPageTitle: "riotgames - Twitch") == .twitch)
        #expect(MediaSite.site(inPageTitle: "Watch on kick.") == .kick)
    }

    @Test func aTitleThatOnlyMentionsASiteDoesNot() {
        #expect(MediaSite.site(inPageTitle: "GEN vs BLG | WORLDS 2026 | Finals") == nil)
        #expect(MediaSite.site(inPageTitle: "YouTube Rewind reaction") == nil)
        #expect(MediaSite.site(inPageTitle: "Sidekick") == nil)
        #expect(MediaSite.site(inPageTitle: "") == nil)
        #expect(MediaSite.site(inPageTitle: "   ") == nil)
    }
}
