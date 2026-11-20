import Foundation
import Testing
@testable import SymbiodockCore

private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [Data] = []
    private var finished = false

    func add(_ line: Data) { lock.withLock { lines.append(line) } }
    func finish() { lock.withLock { finished = true } }
    var texts: [String] { lock.withLock { lines.map { String(decoding: $0, as: UTF8.self) } } }
    var isFinished: Bool { lock.withLock { finished } }
    var byteCounts: [Int] { lock.withLock { lines.map(\.count) } }
}

/// Collects a pipe's lines in the background, so a test never waits on a read that hangs.
private func collect(_ pipe: Pipe) -> LineBox {
    let box = LineBox()
    let lines = PipeLines.lines(from: pipe.fileHandleForReading)
    Task.detached {
        for await line in lines { box.add(line) }
        box.finish()
    }
    return box
}

private func wait(
    upTo limit: Duration = .seconds(3), until condition: @Sendable () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@Suite struct LineSplitterTests {
    @Test func cutsAtLineFeedsAndKeepsTheRestForLater() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("one\ntwo\nthr".utf8)) == [Data("one".utf8), Data("two".utf8)])
        #expect(splitter.append(Data("ee".utf8)) == [])
        #expect(splitter.append(Data("\n".utf8)) == [Data("three".utf8)])
    }

    @Test func leavesOutEmptyLines() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("\n\na\n\n".utf8)) == [Data("a".utf8)])
    }

    /// The helper writes these unescaped inside titles; only 0x0A ends a line.
    @Test func doesNotCutAtUnicodeLineSeparators() {
        var splitter = LineSplitter()
        let text = "a\u{2028}b\u{2029}c\u{0085}d\r"
        #expect(splitter.append(Data("\(text)\n".utf8)) == [Data(text.utf8)])
    }
}

@Suite struct PipeLinesTests {
    @Test func deliversLinesAndEndsWhenTheWriterCloses() async {
        let pipe = Pipe()
        let box = collect(pipe)
        pipe.fileHandleForWriting.write(Data("first\nsecond\n".utf8))
        pipe.fileHandleForWriting.closeFile()

        #expect(await wait { box.isFinished })
        #expect(box.texts == ["first", "second"])
    }

    /// The two helpers are read at the same time, and one of them can stay quiet for hours.
    /// `FileHandle.bytes` reads every handle on one serial queue with a blocking `read`, so
    /// the quiet pipe held back the other one's lines.
    @Test func aSilentPipeDoesNotHoldBackAnotherOne() async {
        let silent = Pipe()
        let talking = Pipe()
        let silentBox = collect(silent)
        // Let the silent pipe's reader start waiting first.
        try? await Task.sleep(for: .milliseconds(200))
        let talkingBox = collect(talking)

        talking.fileHandleForWriting.write(Data("hello\n".utf8))

        #expect(await wait { talkingBox.texts == ["hello"] })
        #expect(silentBox.texts.isEmpty)
        silent.fileHandleForWriting.closeFile()
        talking.fileHandleForWriting.closeFile()
    }

    /// A line with artwork is far larger than a pipe's 64 KB buffer.
    @Test func deliversALineLargerThanThePipeBufferWhileAnotherPipeIsSilent() async {
        let silent = Pipe()
        let talking = Pipe()
        _ = collect(silent)
        try? await Task.sleep(for: .milliseconds(200))
        let box = collect(talking)

        let writer = talking.fileHandleForWriting
        Task.detached {
            writer.write(Data(repeating: 0x41, count: 400_000) + Data("\n".utf8))
        }

        #expect(await wait { box.byteCounts == [400_000] })
        silent.fileHandleForWriting.closeFile()
        writer.closeFile()
    }
}
