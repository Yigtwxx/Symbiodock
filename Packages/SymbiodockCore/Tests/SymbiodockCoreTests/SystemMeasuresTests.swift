import Foundation
import Testing
@testable import SymbiodockCore

struct SystemMeasuresTests {
    @Test func cpuUseIsTheBusyShareBetweenTwoReadings() {
        let fraction = CPUUsage.fraction(
            previous: CPUTicks(busy: 1_000, total: 10_000), current: CPUTicks(busy: 1_250, total: 11_000))
        #expect(fraction == 0.25)
    }

    @Test func cpuUseNeedsTwoReadingsThatAdvance() {
        let ticks = CPUTicks(busy: 1_000, total: 10_000)
        #expect(CPUUsage.fraction(previous: nil, current: ticks) == nil)
        #expect(CPUUsage.fraction(previous: ticks, current: nil) == nil)
        #expect(CPUUsage.fraction(previous: ticks, current: ticks) == nil)
        // The counters are 32-bit in the kernel and wrap.
        #expect(CPUUsage.fraction(previous: ticks, current: CPUTicks(busy: 10, total: 90)) == nil)
        #expect(CPUUsage.fraction(previous: ticks, current: CPUTicks(busy: 900, total: 12_000)) == nil)
    }

    @Test func cpuUseNeverPassesOne() {
        let fraction = CPUUsage.fraction(
            previous: CPUTicks(busy: 0, total: 100), current: CPUTicks(busy: 300, total: 200))
        #expect(fraction == 1)
    }

    @Test func usedMemoryIsAppWiredAndCompressed() {
        let pages = MemoryPages(internalPages: 1_000, purgeable: 100, wired: 200, compressed: 50)
        #expect(MemoryUsage.used(pages, pageSize: 16_384) == 1_150 * 16_384)
    }

    @Test func purgeableMemoryNeverMakesTheSumNegative() {
        let pages = MemoryPages(internalPages: 10, purgeable: 100, wired: 2, compressed: 1)
        #expect(MemoryUsage.used(pages, pageSize: 4_096) == 3 * 4_096)
    }

    @Test func memoryFractionIsUsedOverTotal() {
        #expect(MemoryUse(used: 12, total: 48).fraction == 0.25)
        #expect(MemoryUse(used: 60, total: 48).fraction == 1)
        #expect(MemoryUse(used: 5, total: 0).fraction == 0)
    }

    @Test func networkSpeedIsBytesPerSecond() {
        let speed = NetworkRate.speed(
            previous: NetworkCounters(interface: "en0", received: 1_000, sent: 500),
            current: NetworkCounters(interface: "en0", received: 5_000, sent: 1_500), elapsed: 2)
        #expect(speed == NetworkSpeed(down: 2_000, up: 500))
    }

    @Test func networkSpeedIsUnknownAcrossAGapAResetOrAnotherInterface() {
        let before = NetworkCounters(interface: "en0", received: 1_000, sent: 500)
        let after = NetworkCounters(interface: "en0", received: 5_000, sent: 1_500)
        #expect(NetworkRate.speed(previous: nil, current: after, elapsed: 2) == nil)
        #expect(NetworkRate.speed(previous: before, current: nil, elapsed: 2) == nil)
        #expect(NetworkRate.speed(previous: before, current: after, elapsed: 0) == nil)
        // The Mac slept in between.
        #expect(NetworkRate.speed(previous: before, current: after, elapsed: 10.5) == nil)
        #expect(NetworkRate.speed(previous: after, current: before, elapsed: 2) == nil)
        let other = NetworkCounters(interface: "en7", received: 9_000, sent: 9_000)
        #expect(NetworkRate.speed(previous: before, current: other, elapsed: 2) == nil)
    }
}
