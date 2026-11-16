import AppKit
import SymbiodockCore

/// Reads and sets a player's own volume through Apple Events. The first event to a player
/// makes macOS ask for Automation access to it.
@MainActor
enum PlayerVolumeScript {
    /// Nil when the player is not running, or does not answer (no Automation access).
    static func read(_ target: VolumeTarget) -> Double? {
        guard isRunning(target),
              case .success(let reply) = AppleScriptRunner.run(script(target, "sound volume"))
        else { return nil }
        return VolumeLevel.fraction(percent: Int(reply.int32Value))
    }

    static func set(_ target: VolumeTarget, to fraction: Double) {
        guard isRunning(target) else { return }
        _ = AppleScriptRunner.run(
            script(target, "set sound volume to \(VolumeLevel.percent(fraction))"))
    }

    /// A player must never be launched by us: every script is guarded by this.
    private static func isRunning(_ target: VolumeTarget) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    /// The players are local: a hung one must not freeze the main thread for two minutes.
    private static func script(_ target: VolumeTarget, _ body: String) -> String {
        """
        tell application "\(target.applicationName)"
            with timeout of 2 seconds
                \(body)
            end timeout
        end tell
        """
    }
}
