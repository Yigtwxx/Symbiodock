import Testing
@testable import SymbiodockCore

struct TemperatureKeysTests {
    @Test func keysAreSortedIntoProcessorAndGraphics() {
        #expect(TemperatureKeys.sensor(forKey: "Tp0D") == .cpu)
        #expect(TemperatureKeys.sensor(forKey: "Te05") == .cpu)
        #expect(TemperatureKeys.sensor(forKey: "Tg0K") == .gpu)
    }

    @Test func otherKeysAreNotTemperaturesOfTheChip() {
        // Battery, palm rest, SSD, and names of the wrong length.
        for name in ["TB0T", "Ts0P", "TH0a", "TG0P", "Tp", "Tp0DD", "FNum", ""] {
            #expect(TemperatureKeys.sensor(forKey: name) == nil)
        }
    }

    @Test func theTypicalValueIsTheMedian() {
        #expect(TemperatureKeys.typical([41, 44, 72]) == 44)
        #expect(TemperatureKeys.typical([41, 44, 46, 72]) == 45)
        #expect(TemperatureKeys.typical([51.5]) == 51.5)
    }

    /// Recorded on an M4 Pro at rest: about half the keys sit on their floor of 40, a few have
    /// no floor and read the die's 36, a few hold a peak. The die sensors read 35.5 then.
    @Test func aCoolChipReadsBelowTheFloorOfItsKeys() {
        let values: [Double] = [40, 40, 40, 40, 40, 36.0, 36.4, 41.2, 48.6, 53.5]
        #expect(abs((TemperatureKeys.typical(values) ?? 0) - 36.2) < 0.0001)
    }

    @Test func withNoKeyBelowTheFloorACoolChipReadsTheFloor() {
        #expect(TemperatureKeys.typical([40, 40, 40, 41.2, 48.6, 60.8]) == 40)
    }

    /// Under load no key is on the floor (recorded: 43.5 to 65.5, median 54.1).
    @Test func aWarmChipReadsTheMedianAndHeldPeaksDoNotPullIt() {
        #expect(TemperatureKeys.typical([43.5, 47.9, 52.0, 54.1, 56.0, 61.3, 70.9]) == 54.1)
        // A few keys on the floor among many above it do not switch the rule.
        #expect(TemperatureKeys.typical([40, 44, 46, 48, 50]) == 46)
    }

    @Test func readingsOutsideTheRangeAreDropped() {
        #expect(TemperatureKeys.typical([-9201.1, 0, 44, 130, .nan]) == 44)
        #expect(TemperatureKeys.typical([0, 500]) == nil)
        #expect(TemperatureKeys.typical([]) == nil)
        #expect(TemperatureKeys.typical([10, 120]) == 65)
    }

    @Test func aSubsetIsSpreadEvenlyAndKeepsItsOrder() {
        #expect(TemperatureKeys.spread(Array(0..<10), limit: 5) == [0, 2, 4, 6, 8])
        #expect(TemperatureKeys.spread(Array(0..<7), limit: 3) == [0, 2, 4])
        #expect(TemperatureKeys.spread(["a", "b"], limit: 5) == ["a", "b"])
        #expect(TemperatureKeys.spread(["a", "b"], limit: 0) == [])
    }
}
