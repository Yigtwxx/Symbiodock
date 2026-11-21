import Testing
@testable import SymbiodockCore

struct SystemLabelsTests {
    @Test func percentIsWholeAndClamped() {
        #expect(SystemLabels.percent(0.314) == "31%")
        #expect(SystemLabels.percent(0.996) == "100%")
        #expect(SystemLabels.percent(1.7) == "100%")
        #expect(SystemLabels.percent(-0.2) == "0%")
        #expect(SystemLabels.percent(nil) == "—")
    }

    @Test func degreesAreWhole() {
        #expect(SystemLabels.degrees(44.6) == "45°")
        #expect(SystemLabels.degrees(nil) == "—")
    }

    @Test func temperatureTiersFollowTheShownNumber() {
        #expect(SystemLabels.tier(79.4) == .normal)
        #expect(SystemLabels.tier(79.5) == .warm)
        #expect(SystemLabels.tier(94.4) == .warm)
        #expect(SystemLabels.tier(94.5) == .hot)
        #expect(SystemLabels.tier(nil) == .normal)
    }

    @Test func ratesUseDecimalUnits() {
        #expect(SystemLabels.rate(0) == "0 KB/s")
        #expect(SystemLabels.rate(-5) == "0 KB/s")
        #expect(SystemLabels.rate(156_400) == "156 KB/s")
        #expect(SystemLabels.rate(999_400) == "999 KB/s")
        #expect(SystemLabels.rate(999_500) == "1.0 MB/s")
        #expect(SystemLabels.rate(1_740_000) == "1.7 MB/s")
        #expect(SystemLabels.rate(41_400_000) == "41.4 MB/s")
        #expect(SystemLabels.rate(1_260_000_000) == "1.3 GB/s")
    }

    @Test func memoryIsInBinaryGigabytes() {
        let gigabyte: UInt64 = 1_073_741_824
        #expect(SystemLabels.gigabytes(gigabyte * 37 / 2) == "18.5")
        #expect(SystemLabels.gigabytes(0) == "0.0")
        #expect(SystemLabels.wholeGigabytes(48 * gigabyte) == "48")
    }
}
