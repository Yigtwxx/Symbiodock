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
        #expect(TemperatureKeys.typical([40, 44, 72]) == 44)
        #expect(TemperatureKeys.typical([40, 44, 46, 72]) == 45)
        #expect(TemperatureKeys.typical([51.5]) == 51.5)
    }

    /// Recorded on an M4 Pro: most keys do not read below 40, a few hold a peak.
    @Test func floorsAndHeldPeaksDoNotPullTheMedian() {
        let values: [Double] = [40, 40, 40, 40, 40, 41.2, 48.6, 60.8, 42.4, 72.2]
        #expect(TemperatureKeys.typical(values) == 40.6)
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
