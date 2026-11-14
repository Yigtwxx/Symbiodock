import Foundation

/// The helper processes this app has started, so they can be stopped synchronously on quit.
///
/// `Process` is not `Sendable`; every access to the dictionary goes through `lock`, and
/// the processes are only used for `isRunning`, `terminate()` and `processIdentifier`.
final class HelperProcesses: @unchecked Sendable {
    /// How long a process gets to react to SIGTERM before it is killed.
    static let gracePeriod: TimeInterval = 1

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func register(_ process: Process) {
        lock.withLock { processes[ObjectIdentifier(process)] = process }
    }

    func unregister(_ process: Process) {
        lock.withLock { _ = processes.removeValue(forKey: ObjectIdentifier(process)) }
    }

    /// SIGTERM to every registered process, then SIGKILL for the ones still alive after the
    /// grace period. Returns at once when nothing runs, and after about a second at most.
    func terminateAll() {
        let running = lock.withLock { Array(processes.values) }.filter(\.isRunning)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(Self.gracePeriod)
        while Date() < deadline, running.contains(where: \.isRunning) {
            usleep(10_000)
        }
        for process in running where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// SIGTERM now; SIGKILL after the grace period if it is still running, so that a stuck
    /// helper cannot keep `waitUntilExit()` from returning.
    static func terminateEscalating(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + gracePeriod) {
            // `isRunning` is false once the process is reaped, so a reused PID is not hit.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Environment for perl: nothing from the app's own environment that could make perl or
    /// dyld load code (PERL5OPT, PERL5LIB, DYLD_*, LD_*).
    static func minimalEnvironment(
        from source: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        for (key, value) in source {
            let allowed = key == "HOME" || key == "TMPDIR" || key == "USER" || key == "LANG"
                || key.hasPrefix("LC_")
            if allowed { environment[key] = value }
        }
        return environment
    }
}
