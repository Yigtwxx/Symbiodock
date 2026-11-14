import Foundation
import Testing
@testable import SymbiodockCore

struct LevelBarsMotionTests {
    @Test func aLevelBarStaysBetweenItsLowestAndFullHeight() {
        for bar in 0..<LevelBarsMotion.barCount {
            for step in 0..<500 {
                let level = LevelBarsMotion.level(ofBar: bar, at: Double(step) * 0.0137)
                #expect(level >= 0.35 - 1e-12 && level <= 1 + 1e-12)
            }
        }
    }

    @Test func aLevelBarRepeatsEveryPeriod() {
        for bar in 0..<LevelBarsMotion.barCount {
            let period = LevelBarsMotion.period(ofBar: bar)
            for step in 0..<50 {
                let time = Double(step) * 0.071
                let now = LevelBarsMotion.level(ofBar: bar, at: time)
                #expect(abs(now - LevelBarsMotion.level(ofBar: bar, at: time + period)) < 1e-9)
                #expect(abs(now - LevelBarsMotion.level(ofBar: bar, at: time + 40 * period)) < 1e-9)
            }
        }
    }

    @Test func theBarsHaveTheirOwnSpeedsAndPhases() {
        #expect(LevelBarsMotion.speeds.count == LevelBarsMotion.phases.count)
        #expect(Set(LevelBarsMotion.speeds).count == LevelBarsMotion.barCount)
        #expect(LevelBarsMotion.restLevel < 0.35)
    }

    @Test func theBarsMoveAsTheyAlwaysHave() {
        // The look the owner checked by hand: these numbers are part of it.
        #expect(LevelBarsMotion.speeds == [5.1, 6.7, 4.3, 7.9])
        #expect(LevelBarsMotion.phases == [0, 1.7, 0.6, 2.9])
        #expect(LevelBarsMotion.restLevel == 0.25)
        // The lowest a moving bar gets, where the sine crosses zero, and its full height.
        let speed = LevelBarsMotion.speeds[0]
        #expect(abs(LevelBarsMotion.level(ofBar: 0, at: 0) - 0.35) < 1e-9)
        #expect(abs(LevelBarsMotion.level(ofBar: 0, at: .pi / (2 * speed)) - 1) < 1e-9)
        #expect(abs(LevelBarsMotion.period(ofBar: 0) - .pi / speed) < 1e-9)
    }
}
