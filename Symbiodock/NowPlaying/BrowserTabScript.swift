import AppKit
import CoreServices
import SymbiodockCore

/// Asks a browser for the URL and title of every open tab, to tell which site is playing.
/// What it returns is used for that comparison only: it must never be logged or stored.
@MainActor
enum BrowserTabScript {
    /// Bundle identifier → the word that browser's scripting dictionary has for a tab's title.
    private static let titleTerms: [String: String] = [
        "com.apple.Safari": "name",
        "com.google.Chrome": "title",
    ]

    static func supports(_ bundleIdentifier: String) -> Bool {
        titleTerms[bundleIdentifier] != nil
    }

    /// nil when the browser cannot be asked: it is not one we know, it is not running, the
    /// user has not allowed Symbiodock to control it, or the script failed.
    static func tabs(of bundleIdentifier: String) async -> [BrowserTab]? {
        guard let titleTerm = titleTerms[bundleIdentifier], isRunning(bundleIdentifier)
        else { return nil }
        guard await automationStatus(for: bundleIdentifier) == noErr else { return nil }
        // The answer can take as long as the user takes; the browser may have quit since,
        // and an Apple Event would launch it again.
        guard isRunning(bundleIdentifier) else { return nil }
        let source = script(bundleIdentifier: bundleIdentifier, titleTerm: titleTerm)
        guard let reply = try? AppleScriptRunner.run(source).get().stringValue else { return nil }
        return BrowserTabs.parse(reply)
    }

    private static func isRunning(_ bundleIdentifier: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    /// Whether Symbiodock may send Apple Events to the app, asking the user the first time.
    /// The system holds the call until the user answers, so it runs off the main thread:
    /// sending the script without asking first would freeze the island behind the prompt.
    private nonisolated static func automationStatus(for bundleIdentifier: String) async -> OSStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
                continuation.resume(returning: AEDeterminePermissionToAutomateTarget(
                    target.aeDesc, typeWildCard, typeWildCard, true))
            }
        }
    }

    /// Two Apple Events per window, however many tabs it has. Fields are joined with the
    /// separators `BrowserTabs.parse` expects (ASCII 31 and 30).
    private static func script(bundleIdentifier: String, titleTerm: String) -> String {
        """
        tell application id "\(bundleIdentifier)"
            with timeout of 2 seconds
                set out to ""
                repeat with w in windows
                    try
                        set tabURLs to URL of tabs of w
                        set tabTitles to \(titleTerm) of tabs of w
                        repeat with i from 1 to count of tabURLs
                            try
                                set out to out & ((item i of tabURLs) as text) & (ASCII character 31) & ((item i of tabTitles) as text) & (ASCII character 30)
                            end try
                        end repeat
                    end try
                end repeat
                return out
            end timeout
        end tell
        """
    }
}
