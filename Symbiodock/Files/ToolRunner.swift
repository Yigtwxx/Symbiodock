import Foundation
import SymbiodockCore

/// Runs one system tool to its end. Follows `MediaRemoteProvider.runToExit`: the process is
/// registered so quitting stops it, and a timeout, a normal exit and a cancel race through a
/// once-only gate.
struct ToolRunner: Sendable {
    let helpers: HelperProcesses

    /// Resumes a continuation exactly once, whichever of exit, timeout or cancel gets there first.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int32?, Never>?
        private var timer: DispatchWorkItem?

        init(_ continuation: CheckedContinuation<Int32?, Never>) { self.continuation = continuation }

        func setTimer(_ item: DispatchWorkItem) { lock.withLock { timer = item } }

        func finish(_ status: Int32?) {
            let (pending, item) = lock.withLock {
                defer { continuation = nil; timer = nil }
                return (continuation, timer)
            }
            item?.cancel()
            pending?.resume(returning: status)
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
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    gate.finish(nil)
                    return
                }
                helpers.register(process)
                let timeout = DispatchWorkItem {
                    HelperProcesses.terminateEscalating(process)
                    helpers.unregister(process)
                    gate.finish(nil)
                }
                gate.setTimer(timeout)
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timeout)
                // Cancelled while launching: the handler below ran before the process existed.
                if Task.isCancelled { HelperProcesses.terminateEscalating(process) }
            }
        } onCancel: {
            HelperProcesses.terminateEscalating(process)
        }
    }
}
