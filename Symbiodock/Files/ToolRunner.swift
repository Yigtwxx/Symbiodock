import Foundation
import SymbiodockCore

/// Runs one system tool to its end. Follows `MediaRemoteProvider.runToExit`: the process is
/// registered so quitting stops it, and a timeout, a normal exit and a cancel race through a
/// once-only gate. The result is only given once the process has ended, so a caller may
/// remove the tool's output at once.
struct ToolRunner: Sendable {
    let helpers: HelperProcesses

    /// Resumes a continuation exactly once, when the process has ended.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int32?, Never>?
        private var timer: DispatchWorkItem?
        private var timedOut = false

        init(_ continuation: CheckedContinuation<Int32?, Never>) { self.continuation = continuation }

        func setTimer(_ item: DispatchWorkItem) { lock.withLock { timer = item } }

        func markTimedOut() { lock.withLock { timedOut = true } }

        /// A tool stopped because it ran out of time has no status, even if it exits cleanly
        /// while being stopped.
        func finish(_ status: Int32?) {
            let (pending, item, late) = lock.withLock {
                defer { continuation = nil; timer = nil }
                return (continuation, timer, timedOut)
            }
            item?.cancel()
            pending?.resume(returning: late ? nil : status)
        }
    }

    /// Exit status, or nil if it could not launch, ran out of time or was cancelled.
    func run(_ command: ToolCommand, timeLimit: Duration) async -> Int32? {
        // A relative path would be read against whatever the tool's working directory is.
        guard command.tool.hasPrefix("/") else { return nil }
        if Task.isCancelled { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.tool)
        process.arguments = command.arguments
        process.environment = HelperProcesses.minimalEnvironment()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let helpers = helpers
        let seconds = Double(timeLimit.components.seconds)
            + Double(timeLimit.components.attoseconds) / 1e18

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
                let gate = Gate(continuation)
                process.terminationHandler = { finished in
                    helpers.unregister(finished)
                    // A signalled process (our own SIGTERM) is not a success or a status.
                    gate.finish(finished.terminationReason == .exit ? finished.terminationStatus : nil)
                }
                // Timer and registration come before the launch: a tool that exits at once
                // still reaches the handler, which cancels the timer and unregisters, so
                // neither is left behind.
                let timeout = DispatchWorkItem {
                    // The result waits for the process to end (the handler above), so the
                    // caller cannot remove the output while the tool still writes it.
                    gate.markTimedOut()
                    HelperProcesses.terminateEscalating(process)
                }
                gate.setTimer(timeout)
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timeout)
                helpers.register(process)
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    helpers.unregister(process)
                    gate.finish(nil)
                    return
                }
                // Cancelled while launching: the handler below ran before the process existed.
                if Task.isCancelled { HelperProcesses.terminateEscalating(process) }
            }
        } onCancel: {
            HelperProcesses.terminateEscalating(process)
        }
    }
}
