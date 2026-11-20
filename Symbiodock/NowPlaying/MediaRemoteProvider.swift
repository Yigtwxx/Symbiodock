import Foundation
import SymbiodockCore
import os

/// System-wide Now Playing through the bundled mediaremote-adapter helper.
///
/// Since macOS 15.4 only entitled processes may use MediaRemote. `/usr/bin/perl` is one,
/// so the helper framework is loaded into perl and prints JSON to stdout.
struct MediaRemoteProvider: NowPlayingProvider {
    struct Paths: Sendable {
        let script: URL
        let framework: URL
        let testClient: URL

        static func inMainBundle() -> Paths? {
            let bundle = Bundle.main
            guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let framework = bundle.privateFrameworksURL?
                      .appendingPathComponent("MediaRemoteAdapter.framework"),
                  let testClient = bundle.url(forAuxiliaryExecutable: "MediaRemoteAdapterTestClient"),
                  FileManager.default.fileExists(atPath: framework.path)
            else { return nil }
            return Paths(script: script, framework: framework, testClient: testClient)
        }
    }

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let commandTimeLimit: TimeInterval = 10
    /// The adapter's own test can take about ten seconds in the worst case; a timeout here
    /// would write off system-wide Now Playing for the whole session.
    private static let availabilityTimeLimit: TimeInterval = 25
    private static let logger = Logger(
        subsystem: "com.yigtwxx.Symbiodock", category: "MediaRemoteProvider")

    let paths: Paths
    let helpers: HelperProcesses

    func isAvailable() async -> Bool {
        await Self.runToExit(
            helpers: helpers, timeLimit: Self.availabilityTimeLimit,
            arguments: [paths.script.path, paths.framework.path, paths.testClient.path, "test"]
        ) == 0
    }

    var updates: AsyncStream<NowPlayingInfo?> {
        let arguments = [
            paths.script.path, paths.framework.path, "stream", "--no-diff", "--debounce=100",
        ]
        let helpers = helpers
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                await Self.streamLoop(
                    helpers: helpers, arguments: arguments, label: "MediaRemote helper"
                ) { line in
                    do {
                        continuation.yield(try MediaRemotePayloadParser.info(fromStreamLine: line))
                    } catch {
                        // The line itself is never logged: it holds what the user is playing.
                        Self.logger.error("Unreadable line from the MediaRemote helper.")
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every app the system knows plays something, the elected one included, from a second
    /// helper. Each access starts a new helper, like `updates`. The stream finishing means the
    /// helper has failed for good; a helper that cannot list the apps reports none.
    var clientUpdates: AsyncStream<[NowPlayingClient]> {
        let arguments = [paths.script.path, paths.framework.path, "stream-clients"]
        let helpers = helpers
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                await Self.streamLoop(
                    helpers: helpers, arguments: arguments, label: "MediaRemote clients helper"
                ) { line in
                    continuation.yield(NowPlayingClientsParser.clients(fromStreamLine: line))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ command: PlaybackCommand) async {
        _ = await Self.runToExit(helpers: helpers, arguments: [
            paths.script.path, paths.framework.path, "send", Self.commandID(command),
        ])
    }

    /// Sends the command to one of the apps `clientUpdates` lists, elected or not.
    func send(_ command: PlaybackCommand, toClient pid: Int32) async {
        _ = await Self.runToExit(helpers: helpers, arguments: [
            paths.script.path, paths.framework.path, "send-to", Self.commandID(command),
            String(pid),
        ])
    }

    /// Command IDs from the adapter's README.
    private static func commandID(_ command: PlaybackCommand) -> String {
        switch command {
        case .togglePlayPause: "2"
        case .next: "4"
        case .previous: "5"
        }
    }

    /// Keeps a streaming helper running and hands each output line to `onLine`. Returns when
    /// `RestartPolicy` gives up on it, or when the task is cancelled.
    private static func streamLoop(
        helpers: HelperProcesses, arguments: [String], label: String,
        onLine: @escaping @Sendable (Data) -> Void
    ) async {
        var policy = RestartPolicy()
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let startedAt = clock.now
            await streamOnce(helpers: helpers, arguments: arguments, label: label, onLine: onLine)
            if Task.isCancelled { return }

            guard let delay = policy.delayAfterRun(lasting: clock.now - startedAt) else {
                logger.error("The \(label, privacy: .public) keeps exiting; giving up on it.")
                return
            }
            try? await Task.sleep(for: delay)
        }
    }

    private static func streamOnce(
        helpers: HelperProcesses, arguments: [String], label: String,
        onLine: @escaping @Sendable (Data) -> Void
    ) async {
        let process = Process()
        process.executableURL = perl
        process.arguments = arguments
        process.environment = HelperProcesses.minimalEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Could not launch the \(label, privacy: .public).")
            return
        }
        helpers.register(process)
        defer { helpers.unregister(process) }

        await withTaskCancellationHandler {
            // Two helpers are read at once; `PipeLines` keeps a quiet one from holding back
            // the other's lines.
            for await line in PipeLines.lines(from: pipe.fileHandleForReading) {
                onLine(line)
            }
        } onCancel: {
            HelperProcesses.terminateEscalating(process)
        }
        // Output closed but the process may linger; make sure the wait below ends.
        HelperProcesses.terminateEscalating(process)
        process.waitUntilExit()
    }

    /// Resumes a continuation exactly once, whichever of exit, timeout or cancel gets there first.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int32, Never>?
        private var timer: DispatchWorkItem?

        init(_ continuation: CheckedContinuation<Int32, Never>) { self.continuation = continuation }

        func setTimer(_ item: DispatchWorkItem) { lock.withLock { timer = item } }

        func finish(_ status: Int32) {
            let (pending, item) = lock.withLock {
                defer { continuation = nil; timer = nil }
                return (continuation, timer)
            }
            item?.cancel()
            pending?.resume(returning: status)
        }
    }

    /// Runs perl with the given arguments and returns its exit status, or -1 if it did not
    /// start, ran out of time (`oneShotTimeLimit`) or was cancelled.
    private static func runToExit(
        helpers: HelperProcesses, timeLimit: TimeInterval = commandTimeLimit, arguments: [String]
    ) async -> Int32 {
        if Task.isCancelled { return -1 }
        let process = Process()
        process.executableURL = perl
        process.arguments = arguments
        process.environment = HelperProcesses.minimalEnvironment()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                let gate = Gate(continuation)
                process.terminationHandler = { finished in
                    helpers.unregister(finished)
                    gate.finish(finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    gate.finish(-1)
                    return
                }
                helpers.register(process)
                let timeout = DispatchWorkItem {
                    HelperProcesses.terminateEscalating(process)
                    helpers.unregister(process)
                    gate.finish(-1)
                }
                gate.setTimer(timeout)
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + timeLimit, execute: timeout)
                // Cancelled while launching: the handler below ran before the process existed.
                if Task.isCancelled { HelperProcesses.terminateEscalating(process) }
            }
        } onCancel: {
            HelperProcesses.terminateEscalating(process)
        }
    }
}
