import AppKit
import SymbiodockCore

/// The app a session runs in: the terminal or editor above the tool's process.
enum HostApp {
    /// Fills in `hostAppPID`: the nearest process, from the tool's own upward, that is a
    /// regular app. A chain that ends in `tmux` or `launchd` has none, and stays nil.
    static func resolving(_ session: AgentSession, in processes: [ProcessSnapshot]) -> AgentSession {
        guard let pid = session.pid else { return session }
        var session = session
        session.hostAppPID = ([pid] + ProcessTree.ancestors(of: pid, in: processes)).first {
            NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular
        }
        return session
    }

    /// Brings the app forward. Opening it again is what reliably activates an app from an
    /// agent app like this one; plain activation is the fallback.
    @MainActor
    static func bringForward(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard let url = app.bundleURL else {
            app.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard error != nil else { return }
            Task { @MainActor in
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
    }
}
