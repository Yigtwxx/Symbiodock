import Testing
@testable import SymbiodockCore

struct BrowserTabsTests {
    private func tab(_ url: String, _ title: String) -> BrowserTab {
        BrowserTab(url: url, title: title)
    }

    @Test func parsesRecordsAndSkipsBrokenOnes() {
        let output = "https://a.com\u{1F}A\u{1E}broken\u{1E}https://b.com\u{1F}B | C\u{1E}"
        #expect(
            BrowserTabs.parse(output) == [tab("https://a.com", "A"), tab("https://b.com", "B | C")])
        #expect(BrowserTabs.parse("") == [])
    }

    @Test func aTabWithNoTitleIsKept() {
        #expect(BrowserTabs.parse("https://a.com\u{1F}\u{1E}") == [tab("https://a.com", "")])
    }

    @Test func theTabWhoseTitleContainsTheTrackIsPlaying() {
        let tabs = [
            tab("https://news.example", "News"),
            tab("https://www.youtube.com/watch?v=1", "(3) GEN vs BLG | Finals - YouTube"),
        ]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "gen vs blg | finals") == tabs[1])
    }

    @Test func aTrackNamedAfterThePageMatchesToo() {
        let tabs = [tab("https://kick.com/x", "x Live Stream")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "x Live Stream | Kick") == tabs[0])
    }

    @Test func amongMatchesAKnownSiteWins() {
        let tabs = [
            tab("https://search.example/?q=song", "Song - Search"),
            tab("https://www.youtube.com/watch?v=2", "Song - YouTube"),
        ]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "Song") == tabs[1])
    }

    @Test func aMatchOnAnUnknownSiteStillWinsOverAnotherTabsKnownSite() {
        let tabs = [
            tab("https://www.youtube.com/", "YouTube"),
            tab("https://radio.example/live", "Morning Show - Radio"),
        ]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "Morning Show") == tabs[1])
    }

    @Test func withNoTitleMatchTheOnlyKnownSiteIsPlaying() {
        let tabs = [
            tab("https://news.example", "News"), tab("https://www.twitch.tv/riot", "riot - Twitch"),
        ]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "Worlds day 3") == tabs[1])
    }

    @Test func twoKnownSitesAndNoTitleMatchIsUndecided() {
        let tabs = [
            tab("https://www.youtube.com/", "YouTube"),
            tab("https://www.twitch.tv/riot", "riot - Twitch"),
        ]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "Worlds day 3") == nil)
    }

    @Test func shortOrEmptyTitlesNeverMatch() {
        let tabs = [tab("https://a.example", "A"), tab("https://b.example", "")]
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "A long track name") == nil)
        #expect(BrowserTabs.playingTab(in: tabs, trackTitle: "") == nil)
        #expect(BrowserTabs.playingTab(in: [], trackTitle: "Anything") == nil)
    }
}
