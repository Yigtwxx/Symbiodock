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
            == CGRect(x: 516, y: 0, width: 480, height: 134))
    }

    @Test func expandedIslandStaysInsideTheLeftEdge() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: leftNotch, screenSize: screen, hasTrack: false)
            == CGRect(x: 0, y: 0, width: 480, height: 134))
    }

    @Test func expandedIslandStaysInsideTheRightEdge() {
        let rightNotch = CGRect(x: 1302, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: rightNotch, screenSize: screen, hasTrack: false)
            == CGRect(x: 1032, y: 0, width: 480, height: 134))
    }

    @Test func expandedIslandIsNeverNarrowerThanTheNotch() {
        let wideNotch = CGRect(x: 500, y: 0, width: 520, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: wideNotch, screenSize: screen, hasTrack: false)
            == CGRect(x: 500, y: 0, width: 520, height: 134))
    }

    @Test func hitRectIsTheFrameGrownByFourPoints() {
        #expect(IslandLayout.hitRect(phase: .collapsed, notch: notch, screenSize: screen, hasTrack: false)
            == CGRect(x: 658, y: -4, width: 196, height: 40))
        #expect(IslandLayout.hitRect(phase: .expanded, notch: notch, screenSize: screen, hasTrack: false)
            == CGRect(x: 512, y: -4, width: 488, height: 142))
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
            == CGRect(x: 516, y: 0, width: 480, height: 134))
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

    @Test func dockedCollapsedIslandLiesFlushAgainstTheVisibleFrame() {
        #expect(floating(.corner(.topLeft)) == CGRect(x: 0, y: 32, width: 200, height: 36))
        #expect(floating(.corner(.bottomRight)) == CGRect(x: 1312, y: 876, width: 200, height: 36))
    }

    @Test func cornersOnAScreenEdgeAreSquareLikeTheNotchs() {
        func radii(_ anchor: IslandAnchor) -> [CGFloat] {
            let r = IslandLayout.cornerRadii(anchor: anchor, radius: 10)
            return [r.topLeading, r.topTrailing, r.bottomLeading, r.bottomTrailing]
        }
        #expect(radii(.notch) == [0, 0, 10, 10])
        #expect(radii(.edge(.top, fraction: 0.3)) == [0, 0, 10, 10])
        #expect(radii(.edge(.bottom, fraction: 0.3)) == [10, 10, 0, 0])
        #expect(radii(.edge(.left, fraction: 0.3)) == [0, 10, 0, 10])
        #expect(radii(.edge(.right, fraction: 0.3)) == [10, 0, 10, 0])
        // In a corner only the corner that points into the display is rounded.
        #expect(radii(.corner(.topLeft)) == [0, 0, 0, 10])
        #expect(radii(.corner(.topRight)) == [0, 0, 10, 0])
        #expect(radii(.corner(.bottomLeft)) == [0, 10, 0, 0])
        #expect(radii(.corner(.bottomRight)) == [10, 0, 0, 0])
    }

    @Test func floatingIslandIgnoresWhetherThereIsATrack() {
        #expect(
            floating(.corner(.topLeft), hasTrack: false)
                == floating(.corner(.topLeft), hasTrack: true))
    }

    @Test func edgeFractionSlidesAlongTheEdge() {
        #expect(floating(.edge(.top, fraction: 0)) == CGRect(x: 0, y: 32, width: 200, height: 36))
        #expect(floating(.edge(.top, fraction: 1)) == CGRect(x: 1312, y: 32, width: 200, height: 36))
        #expect(floating(.edge(.top, fraction: 0.5)) == CGRect(x: 656, y: 32, width: 200, height: 36))
        #expect(floating(.edge(.left, fraction: 0.5)) == CGRect(x: 0, y: 454, width: 200, height: 36))
        #expect(floating(.edge(.right, fraction: 1)) == CGRect(x: 1312, y: 876, width: 200, height: 36))
        #expect(floating(.edge(.bottom, fraction: 0)) == CGRect(x: 0, y: 876, width: 200, height: 36))
    }

    @Test func expandingGrowsTowardTheInside() {
        #expect(
            floating(.corner(.bottomRight), .expanded)
                == CGRect(x: 1032, y: 778, width: 480, height: 134))
        #expect(
            floating(.edge(.bottom, fraction: 0.5), .expanded)
                == CGRect(x: 516, y: 778, width: 480, height: 134))
        #expect(
            floating(.edge(.right, fraction: 0), .expanded)
                == CGRect(x: 1032, y: 32, width: 480, height: 134))
    }

    @Test func floatingHitRectIsTheFrameGrownByFourPoints() {
        #expect(
            IslandLayout.hitRect(
                anchor: .corner(.topLeft), phase: .collapsed, notch: notch,
                visibleFrame: visible, screenSize: screen, hasTrack: false)
                == CGRect(x: -4, y: 28, width: 208, height: 44))
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
        #expect(floating(.edge(.top, fraction: 0.01)).minX == 0)
        #expect(floating(.edge(.top, fraction: 0.99)).maxX == 1512)
        #expect(floating(.edge(.top, fraction: 0.01), .expanded).minX == 0)
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

    @Test func floatingIslandNeverSitsUnderTheNotch() {
        // With the menu bar hidden the visible frame reaches the top of the display.
        let full = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let middle = IslandLayout.frame(
            anchor: .edge(.top, fraction: 0.5), phase: .collapsed, notch: notch,
            visibleFrame: full, screenSize: screen, hasTrack: false)
        #expect(!middle.intersects(notch))
        #expect(middle == CGRect(x: 656, y: 40, width: 200, height: 36))

        let expanded = IslandLayout.frame(
            anchor: .edge(.top, fraction: 0.5), phase: .expanded, notch: notch,
            visibleFrame: full, screenSize: screen, hasTrack: false)
        #expect(!expanded.intersects(notch))
        #expect(expanded.minY == 40)

        // Away from the notch the top edge is still the top edge.
        let aside = IslandLayout.frame(
            anchor: .edge(.top, fraction: 0.1), phase: .collapsed, notch: notch,
            visibleFrame: full, screenSize: screen, hasTrack: false)
        #expect(aside.minY == 0)
    }

    @Test func hoveringADockedIslandNeverMovesItFromUnderThePointer() {
        // Otherwise an island beside the notch would open, jump down, lose the pointer,
        // close, and open again, forever.
        let frames = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),    // menu bar hidden
            CGRect(x: 0, y: 32, width: 1512, height: 880),   // menu bar and Dock
            CGRect(x: 0, y: 24, width: 1512, height: 958),
        ]
        for visible in frames {
            for step in 0...200 {
                let anchor = IslandAnchor.edge(.top, fraction: Double(step) / 200)
                let collapsed = IslandLayout.hitRect(
                    anchor: anchor, phase: .collapsed, notch: notch,
                    visibleFrame: visible, screenSize: screen, hasTrack: false)
                let expanded = IslandLayout.hitRect(
                    anchor: anchor, phase: .expanded, notch: notch,
                    visibleFrame: visible, screenSize: screen, hasTrack: false)
                #expect(expanded.contains(collapsed), "fraction \(Double(step) / 200), visible \(visible)")
            }
        }
    }
}
