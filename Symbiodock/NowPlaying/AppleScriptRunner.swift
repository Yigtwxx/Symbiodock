import Foundation
import os

/// Runs AppleScript on the main actor (NSAppleScript is not thread-safe).
@MainActor
enum AppleScriptRunner {
    enum Failure: Error {
        /// The user has not allowed Symbiodock to control the target app.
        case notPermitted
        case other
    }

    /// errAEEventNotPermitted
    private static let notPermittedCode = -1743

    private static let logger = Logger(
        subsystem: "com.yigtwxx.Symbiodock", category: "AppleMusicProvider")

    /// Each source is compiled once; compiling on every call would be wasted work.
    private static var scripts: [String: NSAppleScript] = [:]

    static func run(_ source: String) -> Result<NSAppleEventDescriptor, Failure> {
        let script: NSAppleScript
        if let cached = scripts[source] {
            script = cached
        } else if let created = NSAppleScript(source: source) {
            scripts[source] = created
            script = created
        } else {
            logger.error("An AppleScript did not compile.")
            return .failure(.other)
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            if code == notPermittedCode { return .failure(.notPermitted) }
            // Only the number is logged: the message and reply can hold track data.
            logger.error("AppleScript failed with error code \(code ?? 0, privacy: .public)")
            return .failure(.other)
        }
        return .success(result)
    }
}
