import Foundation
import SymbiodockCore

/// Sits between the Now Playing service and the island and says which site a browser is
/// playing. The system names only the browser, so the browser is asked for its tabs.
@MainActor
final class SiteResolver {
    /// What a lookup is for. A new title in the same browser is a new lookup.
    private struct Key: Equatable {
        var bundleIdentifier: String
        var title: String
    }

    private let onUpdate: @MainActor (NowPlayingInfo?) -> Void
    private var latest: NowPlayingInfo?
    /// The answer of the last finished lookup; a nil site means the tabs did not tell.
    private var resolved: (key: Key, site: MediaSite?)?
    /// One lookup at a time: while the consent prompt is up, every update would add another.
    private var isLookingUp = false

    init(onUpdate: @escaping @MainActor (NowPlayingInfo?) -> Void) {
        self.onUpdate = onUpdate
    }

    /// Passes `info` on at once with the best site known so far, and again when the browser
    /// has answered for a track it has not been asked about yet.
    func publish(_ info: NowPlayingInfo?) {
        latest = info
        guard var info, let key = Self.key(for: info) else {
            onUpdate(info)
            return
        }
        let named = MediaSite.site(inPageTitle: info.title)
        if let resolved, resolved.key == key {
            info.site = resolved.site ?? named
        } else {
            // Until the browser answers, the next track is most likely on the same site;
            // falling back to the browser's icon in between would make the icon flicker.
            let previous = resolved?.key.bundleIdentifier == key.bundleIdentifier
                ? resolved?.site : nil
            info.site = named ?? previous
            lookUp(key)
        }
        onUpdate(info)
    }

    private static func key(for info: NowPlayingInfo) -> Key? {
        guard let identifier = info.sourceBundleIdentifier, BrowserTabScript.supports(identifier)
        else { return nil }
        return Key(bundleIdentifier: identifier, title: info.title)
    }

    private func lookUp(_ key: Key) {
        guard !isLookingUp else { return }
        isLookingUp = true
        Task { [weak self] in
            let tabs = await BrowserTabScript.tabs(of: key.bundleIdentifier)
            self?.finishLookup(key, tabs: tabs)
        }
    }

    private func finishLookup(_ key: Key, tabs: [BrowserTab]?) {
        isLookingUp = false
        let site = tabs
            .flatMap { BrowserTabs.playingTab(in: $0, trackTitle: key.title) }
            .flatMap { MediaSite.site(forPageURL: $0.url) }
        resolved = (key, site)
        // Publishing again either uses this answer or, if the track changed while the
        // browser was asked, starts the lookup for the track that plays now.
        if let latest, Self.key(for: latest) != nil { publish(latest) }
    }
}

/// The same for the other apps the system lists: the first browser among them that holds a
/// media slot gets its site. A browser that is not shown is never asked for its tabs (no
/// AppleScript, no Automation prompt); a second shown browser keeps the browser's own icon.
@MainActor
final class ClientSiteResolver {
    private let onUpdate: @MainActor ([NowPlayingClient]) -> Void
    private var latest: [NowPlayingClient] = []
    /// The processes of the listed apps that hold a media slot.
    private var shownPIDs: Set<Int32> = []
    /// The client whose info goes through `resolver`.
    private var browserPID: Int32?
    private lazy var resolver = SiteResolver { [weak self] info in self?.resolved(info) }

    init(onUpdate: @escaping @MainActor ([NowPlayingClient]) -> Void) {
        self.onUpdate = onUpdate
    }

    func publish(_ clients: [NowPlayingClient]) {
        latest = clients
        resolve()
    }

    /// The island's slots changed. They are built from what `publish` passed on, so a browser
    /// that has just taken a slot is asked from here.
    func show(_ slots: [NowPlayingSlot]) {
        let pids = Set(slots.compactMap(\.origin.clientPID))
        guard pids != shownPIDs else { return }
        shownPIDs = pids
        resolve()
    }

    private func resolve() {
        let browser = latest.first { client in
            shownPIDs.contains(client.pid)
                && client.info.sourceBundleIdentifier.map(BrowserTabScript.supports) == true
        }
        browserPID = browser?.pid
        resolver.publish(browser?.info)
    }

    private func resolved(_ info: NowPlayingInfo?) {
        var clients = latest
        if let info, let index = clients.firstIndex(where: {
            $0.pid == browserPID && $0.info.title == info.title
        }) {
            clients[index].info.site = info.site
        }
        onUpdate(clients)
    }
}
