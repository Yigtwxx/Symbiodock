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

    // MARK: Floating anchors

    let visible = CGRect(x: 0, y: 32, width: 1512, height: 880)

    private func floating(
        _ anchor: IslandAnchor, _ phase: IslandPhase = .collapsed, hasTrack: Bool = false
    ) -> CGRect {
        IslandLayout.frame(
            anchor: anchor, phase: phase, notch: notch, visibleFrame: visible,
            screenSize: screen, hasTrack: hasTrack)
    }

    @Test func notchAnchorMatchesTheNotchLayout() {
        for phase in [IslandPhase.collapsed, .expanded] {
            for hasTrack in [false, true] {
                #expect(
                    floating(.notch, phase, hasTrack: hasTrack)
                        == IslandLayout.frame(
                            phase: phase, notch: notch, screenSize: screen, hasTrack: hasTrack))
            }
        }
    }

    @Test func floatingCollapsedIslandIsACapsuleInsideTheVisibleFrame() {
        #expect(floating(.corner(.topLeft)) == CGRect(x: 8, y: 40, width: 200, height: 36))
        #expect(floating(.corner(.bottomRight)) == CGRect(x: 1304, y: 868, width: 200, height: 36))
    }

    @Test func floatingIslandIgnoresWhetherThereIsATrack() {
        #expect(
            floating(.corner(.topLeft), hasTrack: false)
                == floating(.corner(.topLeft), hasTrack: true))
    }

    @Test func edgeFractionSlidesAlongTheEdge() {
        #expect(floating(.edge(.top, fraction: 0)) == CGRect(x: 8, y: 40, width: 200, height: 36))
        #expect(floating(.edge(.top, fraction: 1)) == CGRect(x: 1304, y: 40, width: 200, height: 36))
        #expect(floating(.edge(.top, fraction: 0.5)) == CGRect(x: 656, y: 40, width: 200, height: 36))
        #expect(floating(.edge(.left, fraction: 0.5)) == CGRect(x: 8, y: 454, width: 200, height: 36))
        #expect(floating(.edge(.right, fraction: 1)) == CGRect(x: 1304, y: 868, width: 200, height: 36))
        #expect(floating(.edge(.bottom, fraction: 0)) == CGRect(x: 8, y: 868, width: 200, height: 36))
    }

    @Test func expandingGrowsTowardTheInside() {
        #expect(
            floating(.corner(.bottomRight), .expanded)
                == CGRect(x: 1144, y: 754, width: 360, height: 150))
        #expect(
            floating(.edge(.bottom, fraction: 0.5), .expanded)
                == CGRect(x: 576, y: 754, width: 360, height: 150))
        #expect(
            floating(.edge(.right, fraction: 0), .expanded)
                == CGRect(x: 1144, y: 40, width: 360, height: 150))
    }

    @Test func floatingHitRectIsTheFrameGrownByFourPoints() {
        #expect(
            IslandLayout.hitRect(
                anchor: .corner(.topLeft), phase: .collapsed, notch: notch,
                visibleFrame: visible, screenSize: screen, hasTrack: false)
                == CGRect(x: 4, y: 36, width: 208, height: 44))
    }
}
