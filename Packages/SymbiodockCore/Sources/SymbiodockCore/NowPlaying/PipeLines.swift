import Foundation
import os

/// Cuts a stream of bytes into lines at 0x0A only. Empty lines are left out.
///
/// `AsyncSequence.lines` also cuts at U+2028, U+2029 and U+0085, which the MediaRemote
/// helper writes unescaped inside titles.
public struct LineSplitter: Sendable {
    private var pending = Data()

    public init() {}

    /// The lines the chunk completes; an unfinished last line is kept for the next chunk.
    public mutating func append(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var rest = chunk[...]
        while let newline = rest.firstIndex(of: 0x0A) {
            pending.append(rest[..<newline])
            if !pending.isEmpty { lines.append(pending) }
            pending = Data()
            rest = rest[(newline + 1)...]
        }
        pending.append(rest)
        return lines
    }
}

/// The output of a helper process, line by line.
public enum PipeLines {
    /// The stream ends when the writing side closes, or when its consumer goes away.
    ///
    /// Not `FileHandle.bytes`: that reads every handle of the process on one serial queue
    /// with a blocking `read`, so a helper that stays quiet holds back the lines of every
    /// other one. Here each handle is read only when it has something.
    public static func lines(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            let splitter = OSAllocatedUnfairLock(initialState: LineSplitter())
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                for line in splitter.withLock({ $0.append(chunk) }) {
                    continuation.yield(line)
                }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}
