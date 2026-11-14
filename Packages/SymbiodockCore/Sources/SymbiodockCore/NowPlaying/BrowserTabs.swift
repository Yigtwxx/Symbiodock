/// One open tab of a browser.
public struct BrowserTab: Equatable, Sendable {
    public var url: String
    public var title: String

    public init(url: String, title: String) {
        self.url = url
        self.title = title
    }
}

/// Reads a browser's tab list and picks the tab the current track plays in.
public enum BrowserTabs {
    /// Between a tab's URL and its title in the tab script's reply.
    public static let fieldSeparator: Character = "\u{1F}"
    /// After every tab in the tab script's reply. Neither can appear in a URL or a title.
    public static let recordSeparator: Character = "\u{1E}"

    /// A title shorter than this says too little to tie a tab to a track.
    private static let minimumMatchLength = 4

    public static func parse(_ output: String) -> [BrowserTab] {
        output.split(separator: recordSeparator).compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count == 2 else { return nil }
            return BrowserTab(url: String(fields[0]), title: String(fields[1]))
        }
    }

    /// The tab that plays `trackTitle`: one whose title contains the track's (a video page is
    /// titled after its video) or is contained in it (a page that describes no track lends
    /// it its title). Among several a known site wins. With none, the only tab on a known
    /// site is taken; two of them cannot be told apart.
    public static func playingTab(in tabs: [BrowserTab], trackTitle: String) -> BrowserTab? {
        let track = trackTitle.lowercased()
        let matches = tabs.filter { tab in
            let title = tab.title.lowercased()
            return contains(title, track) || contains(track, title)
        }
        func isKnown(_ tab: BrowserTab) -> Bool { MediaSite.site(forPageURL: tab.url) != nil }
        if let match = matches.first(where: isKnown) ?? matches.first { return match }

        let known = tabs.filter(isKnown)
        return known.count == 1 ? known[0] : nil
    }

    private static func contains(_ text: String, _ part: String) -> Bool {
        part.count >= minimumMatchLength && text.contains(part)
    }
}
