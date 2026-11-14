import CoreGraphics
import Testing
@testable import SymbiodockCore

struct IslandLayoutTests {
    let notch = CGRect(x: 662, y: 0, width: 188, height: 32)
    let screen = CGSize(width: 1512, height: 982)

    @Test func collapsedIslandIsExactlyTheNotch() {
        #expect(IslandLayout.frame(phase: .collapsed, notch: notch, screenSize: screen, hasTrack: false) == notch)
    }

    @Test func expandedIslandIsCenteredOnTheNotchAndHangsFromTheTop() {
        #expect(IslandLayout.frame(phase: .expanded, notch: notch, screenSize: screen, hasTrack: false)
            == CGRect(x: 576, y: 0, width: 360, height: 150))
    }

    @Test func expandedIslandStaysInsideTheLeftEdge() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: leftNotch, screenSize: screen, hasTrack: false)
            == CGRect(x: 0, y: 0, width: 360, height: 150))
    }

    @Test func expandedIslandStaysInsideTheRightEdge() {
        let rightNotch = CGRect(x: 1302, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: rightNotch, screenSize: screen, hasTrack: false)
            == CGRect(x: 1152, y: 0, width: 360, height: 150))
    }

    @Test func expandedIslandIsNeverNarrowerThanTheNotch() {
        let wideNotch = CGRect(x: 500, y: 0, width: 400, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: wideNotch, screenSize: screen, hasTrack: false)
            == CGRect(x: 500, y: 0, width: 400, height: 150))
    }

    @Test func hitRectIsTheFrameGrownByFourPoints() {
        #expect(IslandLayout.hitRect(phase: .collapsed, notch: notch, screenSize: screen, hasTrack: false)
            == CGRect(x: 658, y: -4, width: 196, height: 40))
        #expect(IslandLayout.hitRect(phase: .expanded, notch: notch, screenSize: screen, hasTrack: false)
            == CGRect(x: 572, y: -4, width: 368, height: 158))
    }

    @Test func collapsedIslandWithATrackGrowsAWingOnEachSide() {
        #expect(IslandLayout.frame(phase: .collapsed, notch: notch, screenSize: screen, hasTrack: true)
            == CGRect(x: 626, y: 0, width: 260, height: 32))
    }

    @Test func collapsedWingsStayOnScreen() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .collapsed, notch: leftNotch, screenSize: screen, hasTrack: true)
            == CGRect(x: 0, y: 0, width: 272, height: 32))
    }

    @Test func expandedIslandIgnoresTheTrack() {
        #expect(IslandLayout.frame(phase: .expanded, notch: notch, screenSize: screen, hasTrack: true)
            == CGRect(x: 576, y: 0, width: 360, height: 150))
    }

    @Test func hitRectFollowsTheWings() {
        #expect(IslandLayout.hitRect(phase: .collapsed, notch: notch, screenSize: screen, hasTrack: true)
            == CGRect(x: 622, y: -4, width: 268, height: 40))
    }
}
