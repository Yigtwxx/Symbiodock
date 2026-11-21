import Foundation
import Testing
@testable import SymbiodockCore

struct SystemMeterTests {
    private let start = Date(timeIntervalSince1970: 1_795_000_000)

    private func reading(
        at seconds: TimeInterval, busy: UInt64, total: UInt64, received: UInt64? = nil,
        temperatures: Temperatures? = nil
    ) -> SystemReading {
        SystemReading(
            date: start.addingTimeInterval(seconds), cpu: CPUTicks(busy: busy, total: total),
            memory: MemoryUse(used: 20, total: 48), gpu: 0.26, temperatures: temperatures,
            counters: received.map { NetworkCounters(interface: "en0", received: $0, sent: $0 / 10) })
    }

    @Test func theFirstReadingOnlyPrimesTheMeter() {
        var meter = SystemMeter()
        #expect(meter.take(reading(at: 0, busy: 100, total: 1_000, received: 5_000)) == nil)
        #expect(meter.history.samples.isEmpty)
    }

    @Test func theSecondReadingGivesUseAndSpeed() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 100, total: 1_000, received: 10_000))
        let snapshot = meter.take(reading(at: 2, busy: 400, total: 2_000, received: 14_000))
        #expect(snapshot?.cpu == 0.3)
        #expect(snapshot?.gpu == 0.26)
        #expect(snapshot?.memory == MemoryUse(used: 20, total: 48))
        #expect(snapshot?.network == NetworkSpeed(down: 2_000, up: 200))
        #expect(snapshot?.isOnline == true)
        #expect(meter.history.samples == [NetworkSpeed(down: 2_000, up: 200)])
    }

    @Test func temperaturesStayUntilTheyAreReadAgain() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, temperatures: Temperatures(cpu: 44, gpu: 37)))
        let second = meter.take(reading(at: 2, busy: 10, total: 200))
        #expect(second?.temperatures == Temperatures(cpu: 44, gpu: 37))
        let third = meter.take(reading(at: 4, busy: 20, total: 300, temperatures: Temperatures(cpu: 51, gpu: nil)))
        #expect(third?.temperatures == Temperatures(cpu: 51, gpu: nil))
    }

    @Test func aGapPrimesAgainAndEmptiesTheGraph() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, received: 1_000))
        _ = meter.take(reading(at: 2, busy: 10, total: 200, received: 2_000))
        #expect(meter.history.samples.count == 1)
        // The tab was hidden, or the Mac slept.
        #expect(meter.take(reading(at: 60, busy: 500, total: 9_000, received: 900_000)) == nil)
        #expect(meter.history.samples.isEmpty)
        let after = meter.take(reading(at: 60.5, busy: 550, total: 9_100, received: 901_000))
        #expect(after?.cpu == 0.5)
        #expect(after?.network == NetworkSpeed(down: 2_000, up: 200))
    }

    @Test func aClockThatWentBackPrimesAgain() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 10, busy: 0, total: 100))
        #expect(meter.take(reading(at: 8, busy: 10, total: 200)) == nil)
    }

    @Test func withoutANetworkTheSnapshotIsOfflineAndTheGraphEmpties() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, received: 1_000))
        _ = meter.take(reading(at: 2, busy: 10, total: 200, received: 2_000))
        let offline = meter.take(reading(at: 4, busy: 20, total: 300))
        #expect(offline?.isOnline == false)
        #expect(offline?.network == nil)
        #expect(offline?.cpu == 0.1)
        #expect(meter.history.samples.isEmpty)
    }

    @Test func aCounterThatWentBackSkipsOneSample() {
        var meter = SystemMeter()
        _ = meter.take(reading(at: 0, busy: 0, total: 100, received: 9_000))
        _ = meter.take(reading(at: 2, busy: 10, total: 200, received: 10_000))
        let reset = meter.take(reading(at: 4, busy: 20, total: 300, received: 50))
        #expect(reset?.isOnline == true)
        #expect(reset?.network == nil)
        #expect(meter.history.samples.count == 1)
    }

    @Test func theGraphKeepsTheLastThirtySamples() {
        var history = NetworkHistory()
        for index in 0..<35 { history.append(NetworkSpeed(down: Double(index), up: 0)) }
        #expect(history.samples.count == 30)
        #expect(history.samples.first?.down == 5)
        #expect(history.samples.last?.down == 34)
    }

    @Test func bothLinesShareOneScale() {
        var history = NetworkHistory()
        history.append(NetworkSpeed(down: 1_000_000, up: 250_000))
        history.append(NetworkSpeed(down: 4_000_000, up: 2_000_000))
        #expect(history.scale == 4_000_000)
        #expect(history.downFractions == [0.25, 1])
        #expect(history.upFractions == [0.0625, 0.5])
    }

    @Test func aQuietNetworkDoesNotFillTheGraph() {
        var history = NetworkHistory()
        history.append(NetworkSpeed(down: 2_000, up: 500))
        // Below 100 KB/s the scale stays there, so idle chatter stays near the floor.
        #expect(history.scale == 100_000)
        #expect(history.downFractions == [0.02])
        #expect(NetworkHistory().scale == 100_000)
    }
}
