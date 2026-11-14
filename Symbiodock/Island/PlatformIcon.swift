import AppKit
import SwiftUI
import SymbiodockCore

/// Where the sound comes from: the logo of the site playing in a browser, otherwise the
/// icon of the app that plays, otherwise a music glyph.
struct PlatformIcon: View {
    let info: NowPlayingInfo
    let size: CGFloat

    var body: some View {
        Group {
            if let image = PlatformIconCache.image(for: info) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(info.site?.displayName ?? info.sourceName)
    }
}

extension MediaSite {
    var displayName: String {
        switch self {
        case .youtube: "YouTube"
        case .kick: "Kick"
        case .twitch: "Twitch"
        }
    }
}

/// Icons already loaded. Views are re-evaluated on every hover and track update; asking
/// the workspace for an app's icon each time would be wasted work.
@MainActor
private enum PlatformIconCache {
    private static var sites: [MediaSite: NSImage] = [:]
    /// A missing app is remembered too, as nil.
    private static var apps: [String: NSImage?] = [:]

    static func image(for info: NowPlayingInfo) -> NSImage? {
        if let site = info.site, let logo = logo(for: site) { return logo }
        guard let identifier = info.sourceBundleIdentifier else { return nil }
        if let cached = apps[identifier] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        apps[identifier] = icon
        return icon
    }

    private static func logo(for site: MediaSite) -> NSImage? {
        if let cached = sites[site] { return cached }
        guard let url = Bundle.main.url(forResource: site.rawValue, withExtension: "svg"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        sites[site] = image
        return image
    }
}
