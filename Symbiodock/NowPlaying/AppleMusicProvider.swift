import AppKit
import SymbiodockCore

/// Now Playing for Apple Music through public APIs: a distributed notification for
/// changes, Apple Events for the details, artwork and commands.
struct AppleMusicProvider: NowPlayingProvider {
    static let bundleIdentifier = "com.apple.Music"

    /// Called with true when the user has denied Automation access, false when it works.
    let onConsentChange: @MainActor @Sendable (_ denied: Bool) -> Void

    /// Music must never be launched by us: every script is guarded by this.
    @MainActor
    static var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func isAvailable() async -> Bool {
        await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
        }
    }

    var updates: AsyncStream<NowPlayingInfo?> {
        let onConsentChange = onConsentChange
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                let watcher = AppleMusicWatcher(
                    continuation: continuation, onConsentChange: onConsentChange)
                watcher.start()
                // Keeps the watcher alive until the consumer goes away.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                }
                watcher.stop()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ command: PlaybackCommand) async {
        let verb = switch command {
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        await MainActor.run {
            guard Self.isMusicRunning else { return }
            _ = AppleScriptRunner.run("tell application \"Music\" to \(verb)")
        }
    }
}

/// Watches Music and yields its state. Lives on the main actor because of NSAppleScript.
@MainActor
private final class AppleMusicWatcher {
    enum Mode {
        /// Refresh when Music posts `com.apple.Music.playerInfo`.
        case notifications
        /// Refresh once per second while Music is running.
        case polling
    }

    /// Switch to `.polling` if the notification is not delivered on this macOS version.
    private static let mode: Mode = .notifications

    private static let stateScript = """
        tell application "Music"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed \
        & (duration of t) & linefeed & (player position) & linefeed & (player state as text)
        end tell
        """
    private static let artworkScript =
        "tell application \"Music\" to get raw data of artwork 1 of current track"

    private let continuation: AsyncStream<NowPlayingInfo?>.Continuation
    private let onConsentChange: @MainActor @Sendable (Bool) -> Void
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var timer: Timer?
    private var artworkKey: String?
    private var artwork: Data?

    init(
        continuation: AsyncStream<NowPlayingInfo?>.Continuation,
        onConsentChange: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        self.continuation = continuation
        self.onConsentChange = onConsentChange
    }

    func start() {
        refresh()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == AppleMusicProvider.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.musicDidQuit() }
        }))

        switch Self.mode {
        case .notifications:
            let center = DistributedNotificationCenter.default()
            observers.append((center, center.addObserver(
                forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }))
        case .polling:
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    /// Never ask a quitting Music for its state: the Apple Event would launch it again.
    private func musicDidQuit() {
        artworkKey = nil
        artwork = nil
        continuation.yield(nil)
    }

    private func refresh() {
        guard AppleMusicProvider.isMusicRunning else {
            continuation.yield(nil)
            return
        }
        switch AppleScriptRunner.run(Self.stateScript) {
        case .failure(.notPermitted):
            onConsentChange(true)
            continuation.yield(nil)
        case .failure(.other):
            continuation.yield(nil)
        case .success(let reply):
            onConsentChange(false)
            guard let output = reply.stringValue,
                  var info = AppleMusicPayloadParser.info(fromScriptOutput: output, at: Date())
            else {
                continuation.yield(nil)
                return
            }
            let key = [info.title, info.artist, info.album ?? ""].joined(separator: "\n")
            if key != artworkKey {
                artworkKey = key
                let data = (try? AppleScriptRunner.run(Self.artworkScript).get())?.data
                artwork = data.flatMap { $0.isEmpty ? nil : $0 }
            }
            info.artworkData = artwork
            continuation.yield(info)
        }
    }
}
