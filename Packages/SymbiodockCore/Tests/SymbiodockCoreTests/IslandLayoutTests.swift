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

    // MARK: Edge fraction is the center's position

    @Test func edgeFractionIsWhereTheCenterSits() {
        let collapsed = floating(.edge(.top, fraction: 400.0 / 1512))
        #expect(abs(collapsed.midX - 400) < 1e-9)

        let expanded = floating(.edge(.top, fraction: 400.0 / 1512), .expanded)
        #expect(abs(expanded.midX - 400) < 1e-9)

        let left = floating(.edge(.left, fraction: 300.0 / 880))
        #expect(abs(left.midY - 332) < 1e-9)
    }

    @Test func releasedIslandSettlesWhereItWasLetGo() {
        let anchor = SnapResolver.anchor(
            forRelease: CGPoint(x: 400, y: 300), notch: notch, visibleFrame: visible)
        let frame = floating(anchor)
        #expect(abs(frame.midX - 400) < 1e-9)
        #expect(floating(anchor, .expanded).midX == frame.midX)
    }

    @Test func centerFractionIsClampedIntoTheUsableArea() {
        #expect(floating(.edge(.top, fraction: 0.01)).minX == 8)
        #expect(floating(.edge(.top, fraction: 0.99)).maxX == 1504)
        #expect(floating(.edge(.top, fraction: 0.01), .expanded).minX == 8)
    }

    // MARK: Drag phases

    @Test func dragPhasesLayOutLikeCollapsed() {
        let anchors: [IslandAnchor] = [.notch, .edge(.left, fraction: 0.3), .corner(.topRight)]
        for anchor in anchors {
            for hasTrack in [false, true] {
                let collapsed = floating(anchor, .collapsed, hasTrack: hasTrack)
                for phase in [IslandPhase.stretching, .detached, .settling] {
                    #expect(floating(anchor, phase, hasTrack: hasTrack) == collapsed, "\(anchor) \(phase)")
                }
            }
        }
    }

    // MARK: Degenerate input

    private func frame(
        _ anchor: IslandAnchor, visible: CGRect, phase: IslandPhase = .collapsed
    ) -> CGRect {
        IslandLayout.frame(
            anchor: anchor, phase: phase, notch: notch, visibleFrame: visible,
            screenSize: screen, hasTrack: false)
    }

    private func isFinite(_ rect: CGRect) -> Bool {
        rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite
    }

    @Test func nonFiniteFractionIsTreatedAsTheMiddle() {
        for value in [Double.nan, .infinity, -.infinity] {
            let result = floating(.edge(.top, fraction: value))
            #expect(isFinite(result))
        }
        #expect(floating(.edge(.top, fraction: .nan)) == floating(.edge(.top, fraction: 0.5)))
    }

    @Test func tinyVisibleFrameFallsBackToItselfAndStaysFinite() {
        let tiny = CGRect(x: 10, y: 20, width: 12, height: 10)
        for anchor in [IslandAnchor.edge(.top, fraction: 0.5), .corner(.bottomRight), .edge(.left, fraction: .nan)] {
            #expect(isFinite(frame(anchor, visible: tiny)))
            #expect(isFinite(frame(anchor, visible: tiny, phase: .expanded)))
        }
        #expect(frame(.corner(.topLeft), visible: tiny).origin == CGPoint(x: 10, y: 20))
        #expect(isFinite(frame(.corner(.topLeft), visible: .null)))
        #expect(isFinite(frame(.edge(.top, fraction: 0.5), visible: .zero)))
    }
}
