import Foundation

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

    static func run(_ source: String) -> Result<NSAppleEventDescriptor, Failure> {
        guard let script = NSAppleScript(source: source) else { return .failure(.other) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            return .failure(code == notPermittedCode ? .notPermitted : .other)
        }
        return .success(result)
    }
}
