import CoreGraphics
import Testing
@testable import SymbiodockCore

struct IslandLayoutTests {
    let notch = CGRect(x: 662, y: 0, width: 188, height: 32)
    let screen = CGSize(width: 1512, height: 982)

    @Test func collapsedIslandIsExactlyTheNotch() {
        #expect(IslandLayout.frame(phase: .collapsed, notch: notch, screenSize: screen) == notch)
    }

    @Test func expandedIslandIsCenteredOnTheNotchAndHangsFromTheTop() {
        #expect(IslandLayout.frame(phase: .expanded, notch: notch, screenSize: screen)
            == CGRect(x: 576, y: 0, width: 360, height: 150))
    }

    @Test func expandedIslandStaysInsideTheLeftEdge() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: leftNotch, screenSize: screen)
            == CGRect(x: 0, y: 0, width: 360, height: 150))
    }

    @Test func expandedIslandStaysInsideTheRightEdge() {
        let rightNotch = CGRect(x: 1302, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: rightNotch, screenSize: screen)
            == CGRect(x: 1152, y: 0, width: 360, height: 150))
    }

    @Test func expandedIslandIsNeverNarrowerThanTheNotch() {
        let wideNotch = CGRect(x: 500, y: 0, width: 400, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: wideNotch, screenSize: screen)
            == CGRect(x: 500, y: 0, width: 400, height: 150))
    }

    @Test func hitRectIsTheFrameGrownByFourPoints() {
        #expect(IslandLayout.hitRect(phase: .collapsed, notch: notch, screenSize: screen)
            == CGRect(x: 658, y: -4, width: 196, height: 40))
        #expect(IslandLayout.hitRect(phase: .expanded, notch: notch, screenSize: screen)
            == CGRect(x: 572, y: -4, width: 368, height: 158))
    }
}
