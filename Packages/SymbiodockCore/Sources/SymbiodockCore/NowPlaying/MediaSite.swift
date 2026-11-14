import Foundation

/// A web site the island can name when the sound comes from a browser.
public enum MediaSite: String, Equatable, Sendable, CaseIterable {
    case youtube
    case kick
    case twitch

    /// Hosts that belong to the site; their subdomains count too.
    private var domains: [String] {
        switch self {
        case .youtube: ["youtube.com", "youtu.be"]
        case .kick: ["kick.com"]
        case .twitch: ["twitch.tv"]
        }
    }

    /// The site a page belongs to, judged by its host alone.
    public static func site(forPageURL url: String) -> MediaSite? {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return nil }
        return allCases.first { site in
            site.domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// The site a page title ends with ("… | Kick", "… - YouTube"). A browser reports the
    /// page title as the track when the page describes no track of its own.
    public static func site(inPageTitle title: String) -> MediaSite? {
        guard let last = title.split(whereSeparator: \.isWhitespace).last else { return nil }
        let word = last.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return allCases.first { $0.rawValue == word }
    }
}
