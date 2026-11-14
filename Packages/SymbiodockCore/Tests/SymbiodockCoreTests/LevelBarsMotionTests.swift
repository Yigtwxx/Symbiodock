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
}
