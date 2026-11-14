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
    private static let maxRestarts = 3
    private static let logger = Logger(
        subsystem: "com.yigtwxx.Symbiodock", category: "MediaRemoteProvider")

    let paths: Paths

    func isAvailable() async -> Bool {
        await Self.runToExit(arguments: [
            paths.script.path, paths.framework.path, paths.testClient.path, "test",
        ]) == 0
    }

    var updates: AsyncStream<NowPlayingInfo?> {
        let paths = paths
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached {
                await Self.streamLoop(paths: paths, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ command: PlaybackCommand) async {
        // Command IDs from the adapter's README.
        let id = switch command {
        case .togglePlayPause: "2"
        case .next: "4"
        case .previous: "5"
        }
        _ = await Self.runToExit(arguments: [
            paths.script.path, paths.framework.path, "send", id,
        ])
    }

    /// Keeps the helper running. Returns when it has been restarted `maxRestarts` times
    /// without staying up, or when the task is cancelled.
    private static func streamLoop(
        paths: Paths, continuation: AsyncStream<NowPlayingInfo?>.Continuation
    ) async {
        var restarts = 0
        while !Task.isCancelled {
            let startedAt = Date()
            await streamOnce(paths: paths, continuation: continuation)
            if Task.isCancelled { return }

            // A helper that ran for a while was working; start counting again.
            if Date().timeIntervalSince(startedAt) > 60 { restarts = 0 }
            guard restarts < maxRestarts else {
                logger.error("The MediaRemote helper keeps exiting; giving up on it.")
                return
            }
            restarts += 1
            try? await Task.sleep(for: .seconds(1 << (restarts - 1)))  // 1 s, 2 s, 4 s
        }
    }

    private static func streamOnce(
        paths: Paths, continuation: AsyncStream<NowPlayingInfo?>.Continuation
    ) async {
        let process = Process()
        process.executableURL = perl
        process.arguments = [
            paths.script.path, paths.framework.path, "stream", "--no-diff", "--debounce=100",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Could not launch the MediaRemote helper.")
            return
        }

        await withTaskCancellationHandler {
            do {
                // Cut lines at 0x0A only: `.lines` also splits at U+2028, U+2029 and U+0085,
                // which the helper writes unescaped inside titles.
                var buffer = Data()
                for try await byte in pipe.fileHandleForReading.bytes {
                    guard byte == 0x0A else {
                        buffer.append(byte)
                        continue
                    }
                    defer { buffer.removeAll(keepingCapacity: true) }
                    if buffer.isEmpty { continue }
                    do {
                        continuation.yield(try MediaRemotePayloadParser.info(fromStreamLine: buffer))
                    } catch {
                        // The line itself is never logged: it holds what the user is playing.
                        logger.error("Unreadable line from the MediaRemote helper.")
                    }
                }
            } catch {
                logger.error("Reading from the MediaRemote helper failed.")
            }
        } onCancel: {
            process.terminate()
        }
        process.waitUntilExit()
    }

    /// Runs perl with the given arguments and returns its exit status, or -1 if it did not start.
    private static func runToExit(arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = perl
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
