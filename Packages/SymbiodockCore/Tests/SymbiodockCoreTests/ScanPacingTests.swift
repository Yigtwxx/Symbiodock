import Foundation
import Testing
@testable import SymbiodockCore

struct ScanPacingTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func theFirstScanStartsAtOnce() {
        #expect(ScanPacing.delay(sinceLastStart: nil, now: start) == 0)
    }

    @Test func aScanTooSoonAfterTheLastWaitsOutTheGap() {
        let delay = ScanPacing.delay(sinceLastStart: start, now: start.addingTimeInterval(0.1))
        #expect(abs(delay - 0.15) < 1e-6)
    }

    @Test func aScanLongAfterTheLastStartsAtOnce() {
        #expect(ScanPacing.delay(sinceLastStart: start, now: start.addingTimeInterval(1)) == 0)
    }

    @Test func aClockThatWentBackNeverWaitsLongerThanTheGap() {
        let delay = ScanPacing.delay(sinceLastStart: start, now: start.addingTimeInterval(-60))
        #expect(delay == ScanPacing.minimumGap)
    }
}
