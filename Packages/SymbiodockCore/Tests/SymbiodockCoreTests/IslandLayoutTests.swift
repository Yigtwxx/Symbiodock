import CoreGraphics
import Testing
@testable import SymbiodockCore

struct IslandLayoutTests {
    let notch = CGRect(x: 662, y: 0, width: 188, height: 32)
    let screen = CGSize(width: 1512, height: 982)

    @Test func collapsedIslandIsExactlyTheNotch() {
        #expect(IslandLayout.frame(phase: .collapsed, notch: notch, screenSize: screen, showsWings: false) == notch)
    }

    @Test func expandedIslandIsCenteredOnTheNotchAndHangsFromTheTop() {
        #expect(IslandLayout.frame(phase: .expanded, notch: notch, screenSize: screen, showsWings: false)
            == CGRect(x: 456, y: 0, width: 600, height: 170))
    }

    @Test func expandedIslandStaysInsideTheLeftEdge() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: leftNotch, screenSize: screen, showsWings: false)
            == CGRect(x: 0, y: 0, width: 600, height: 170))
    }

    @Test func expandedIslandStaysInsideTheRightEdge() {
        let rightNotch = CGRect(x: 1302, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: rightNotch, screenSize: screen, showsWings: false)
            == CGRect(x: 912, y: 0, width: 600, height: 170))
    }

    @Test func expandedIslandIsNeverNarrowerThanTheNotch() {
        let wideNotch = CGRect(x: 406, y: 0, width: 700, height: 32)

        #expect(IslandLayout.frame(phase: .expanded, notch: wideNotch, screenSize: screen, showsWings: false)
            == CGRect(x: 406, y: 0, width: 700, height: 170))
    }

    @Test func hitRectIsTheFrameGrownByFourPoints() {
        #expect(IslandLayout.hitRect(phase: .collapsed, notch: notch, screenSize: screen, showsWings: false)
            == CGRect(x: 658, y: -4, width: 196, height: 40))
        #expect(IslandLayout.hitRect(phase: .expanded, notch: notch, screenSize: screen, showsWings: false)
            == CGRect(x: 452, y: -4, width: 608, height: 178))
    }

    @Test func collapsedIslandWithWingsGrowsAWingOnEachSide() {
        #expect(IslandLayout.frame(phase: .collapsed, notch: notch, screenSize: screen, showsWings: true)
            == CGRect(x: 626, y: 0, width: 260, height: 32 + IslandLayout.notchLip))
    }

    @Test func theIslandWithWingsReachesJustBelowTheNotch() {
        #expect(IslandLayout.notchLip > 0 && IslandLayout.notchLip <= 3)
        // Without wings it is the notch itself, and cannot be seen.
        #expect(IslandLayout.frame(phase: .collapsed, notch: notch, screenSize: screen, showsWings: false) == notch)
    }

    @Test func collapsedWingsStayOnScreen() {
        let leftNotch = CGRect(x: 10, y: 0, width: 200, height: 32)

        #expect(IslandLayout.frame(phase: .collapsed, notch: leftNotch, screenSize: screen, showsWings: true)
            == CGRect(x: 0, y: 0, width: 272, height: 32 + IslandLayout.notchLip))
    }

    @Test func expandedIslandIgnoresTheWings() {
        #expect(IslandLayout.frame(phase: .expanded, notch: notch, screenSize: screen, showsWings: true)
            == CGRect(x: 456, y: 0, width: 600, height: 170))
    }

    @Test func hitRectFollowsTheWings() {
        #expect(IslandLayout.hitRect(phase: .collapsed, notch: notch, screenSize: screen, showsWings: true)
            == CGRect(x: 622, y: -4, width: 268, height: 40 + IslandLayout.notchLip))
    }

    // MARK: Floating anchors

    let visible = CGRect(x: 0, y: 32, width: 1512, height: 880)

    private func floating(
        _ anchor: IslandAnchor, _ phase: IslandPhase = .collapsed, showsWings: Bool = false
    ) -> CGRect {
        IslandLayout.frame(
            anchor: anchor, phase: phase, notch: notch, visibleFrame: visible,
            screenSize: screen, showsWings: showsWings)
    }

    @Test func notchAnchorMatchesTheNotchLayout() {
        for phase in [IslandPhase.collapsed, .expanded] {
            for showsWings in [false, true] {
                #expect(
                    floating(.notch, phase, showsWings: showsWings)
                        == IslandLayout.frame(
                            phase: phase, notch: notch, screenSize: screen, showsWings: showsWings))
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

    @Test func floatingIslandIgnoresWhetherThereAreWings() {
        #expect(
            floating(.corner(.topLeft), showsWings: false)
                == floating(.corner(.topLeft), showsWings: true))
    }

    @Test func edgeFractionSlidesAlongTheEdge() {
        #expect(floating(.edge(.top, fraction: 0)) == CGRect(x: 0, y: 32, width: 200, height: 36))
        #expect(floating(.edge(.top, fraction: 1)) == CGRect(x: 1312, y: 32, width: 200, height: 36))
        #expect(floating(.edge(.top, fraction: 0.5)) == CGRect(x: 656, y: 32, width: 200, height: 36))
        #expect(floating(.edge(.left, fraction: 0.5)) == CGRect(x: 0, y: 387, width: 36, height: 170))
        #expect(floating(.edge(.right, fraction: 1)) == CGRect(x: 1476, y: 742, width: 36, height: 170))
        #expect(floating(.edge(.bottom, fraction: 0)) == CGRect(x: 0, y: 876, width: 200, height: 36))
    }

    @Test func expandingGrowsTowardTheInside() {
        #expect(
            floating(.corner(.bottomRight), .expanded)
                == CGRect(x: 912, y: 742, width: 600, height: 170))
        #expect(
            floating(.edge(.bottom, fraction: 0.5), .expanded)
                == CGRect(x: 456, y: 742, width: 600, height: 170))
        #expect(
            floating(.edge(.right, fraction: 0), .expanded)
                == CGRect(x: 912, y: 32, width: 600, height: 170))
    }

    // MARK: Side docking

    @Test func onlyLeftAndRightEdgesAreSideDocked() {
        #expect(IslandLayout.isSideDocked(.edge(.left, fraction: 0.5)))
        #expect(IslandLayout.isSideDocked(.edge(.right, fraction: 0.2)))
        for anchor in [IslandAnchor.notch, .edge(.top, fraction: 0.5), .edge(.bottom, fraction: 0.5),
                       .corner(.topLeft), .corner(.bottomRight)] {
            #expect(!IslandLayout.isSideDocked(anchor), "\(anchor)")
        }
    }

    @Test func sideDockedIslandIsAVerticalStripFlushWithItsEdge() {
        let left = floating(.edge(.left, fraction: 0.5))
        #expect(left.size == IslandLayout.sideCollapsedSize)
        #expect(left.minX == visible.minX)
        #expect(abs(left.midY - visible.midY) < 1e-9)

        let right = floating(.edge(.right, fraction: 0.5))
        #expect(right.size == IslandLayout.sideCollapsedSize)
        #expect(right.maxX == visible.maxX)
    }

    @Test func sideStripOpensSidewaysAroundTheSameCenter() {
        let collapsed = floating(.edge(.right, fraction: 0.4))
        let expanded = floating(.edge(.right, fraction: 0.4), .expanded)
        #expect(expanded.width == IslandLayout.expandedSize.width)
        #expect(expanded.maxX == visible.maxX)
        #expect(abs(expanded.midY - collapsed.midY) < 1e-9)
    }

    @Test func sideStripStaysInsideTheVisibleFrame() {
        #expect(floating(.edge(.left, fraction: 0)).minY == visible.minY)
        #expect(floating(.edge(.left, fraction: 1)).maxY == visible.maxY)
    }

    @Test func cornersAndHorizontalEdgesKeepTheHorizontalIsland() {
        for anchor in [IslandAnchor.edge(.top, fraction: 0.5), .edge(.bottom, fraction: 0.5),
                       .corner(.topLeft), .corner(.bottomRight)] {
            #expect(floating(anchor).size == IslandLayout.floatingCollapsedSize, "\(anchor)")
        }
    }

    @Test func floatingHitRectIsTheFrameGrownByFourPoints() {
        #expect(
            IslandLayout.hitRect(
                anchor: .corner(.topLeft), phase: .collapsed, notch: notch,
                visibleFrame: visible, screenSize: screen, showsWings: false)
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
            for showsWings in [false, true] {
                let collapsed = floating(anchor, .collapsed, showsWings: showsWings)
                for phase in [IslandPhase.stretching, .detached, .settling] {
                    #expect(floating(anchor, phase, showsWings: showsWings) == collapsed, "\(anchor) \(phase)")
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
            screenSize: screen, showsWings: false)
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

    @Test func islandOnTheTopEdgeSlidesAsideFromTheNotch() {
        // Docked against the whole display, the top edge runs through the camera housing.
        let full = CGRect(x: 0, y: 0, width: 1512, height: 982)
        func top(_ fraction: Double, _ phase: IslandPhase) -> CGRect {
            IslandLayout.frame(
                anchor: .edge(.top, fraction: fraction), phase: phase, notch: notch,
                visibleFrame: full, screenSize: screen, showsWings: false)
        }

        // Left of the notch's middle it stays on the bezel and stops 8 pt short of the notch.
        #expect(top(0.4, .collapsed) == CGRect(x: 454, y: 0, width: 200, height: 36))
        #expect(top(0.4, .expanded) == CGRect(x: 54, y: 0, width: 600, height: 170))
        // Right of it, the same on the other side.
        #expect(top(0.6, .collapsed) == CGRect(x: 858, y: 0, width: 200, height: 36))
        #expect(top(0.6, .expanded) == CGRect(x: 858, y: 0, width: 600, height: 170))

        // Clear of the notch when closed, it does not move; only the open island shifts.
        #expect(top(0.25, .collapsed) == CGRect(x: 278, y: 0, width: 200, height: 36))
        #expect(top(0.25, .expanded).maxX == 654)

        // Away from the notch nothing changes.
        #expect(top(0.1, .collapsed).minY == 0)
        #expect(top(0.1, .expanded).minX == 0)
    }

    @Test func islandHangsBelowTheNotchWhenItCannotOpenBesideIt() {
        // A scaled-down display: 479.5 pt beside the notch, less than the open island.
        let narrow = CGSize(width: 1147, height: 745)
        let notch = CGRect(x: 479.5, y: 0, width: 188, height: 32)
        let full = CGRect(origin: .zero, size: narrow)
        for phase in [IslandPhase.collapsed, .expanded] {
            let rect = IslandLayout.frame(
                anchor: .edge(.top, fraction: 0.45), phase: phase, notch: notch,
                visibleFrame: full, screenSize: narrow, showsWings: false)
            #expect(!rect.intersects(notch))
            #expect(rect.minY == 40)
        }
    }

    @Test func sideStripNeverSlidesOffItsEdge() {
        // A strip at the top of a narrow display opens across the notch: it moves down,
        // not sideways, so it stays on its edge.
        let narrow = CGSize(width: 700, height: 600)
        let notch = CGRect(x: 256, y: 0, width: 188, height: 32)
        let rect = IslandLayout.frame(
            anchor: .edge(.left, fraction: 0), phase: .collapsed, notch: notch,
            visibleFrame: CGRect(origin: .zero, size: narrow), screenSize: narrow,
            showsWings: false)
        #expect(rect.minX == 0)
        #expect(rect.minY == 40)
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
            for edge in [ScreenEdge.top, .left, .right] {
                for step in 0...200 {
                    let anchor = IslandAnchor.edge(edge, fraction: Double(step) / 200)
                    let collapsed = IslandLayout.hitRect(
                        anchor: anchor, phase: .collapsed, notch: notch,
                        visibleFrame: visible, screenSize: screen, showsWings: false)
                    let expanded = IslandLayout.hitRect(
                        anchor: anchor, phase: .expanded, notch: notch,
                        visibleFrame: visible, screenSize: screen, showsWings: false)
                    #expect(
                        expanded.contains(collapsed),
                        "\(edge) fraction \(Double(step) / 200), visible \(visible)")
                }
            }
        }
    }

    @Test func dockedEdgesAreTheOnesTheIslandTouches() {
        #expect(IslandLayout.dockedEdges(anchor: .notch) == [.top])
        #expect(IslandLayout.dockedEdges(anchor: .edge(.left, fraction: 0.5)) == [.left])
        #expect(IslandLayout.dockedEdges(anchor: .edge(.bottom, fraction: 0.2)) == [.bottom])
        #expect(IslandLayout.dockedEdges(anchor: .corner(.topRight)) == [.top, .right])
        #expect(IslandLayout.dockedEdges(anchor: .corner(.bottomLeft)) == [.bottom, .left])
    }

    @Test func theBubbleSitsLeftOfTheWingsCentredInTheNotchBand() {
        // The island with wings starts at 662 − 36 = 626.
        #expect(IslandLayout.bubbleFrame(notch: notch, screenSize: screen)
            == CGRect(x: 592, y: 2, width: 28, height: 28))
    }

    @Test func theBubbleShrinksWithAShortNotch() {
        let short = CGRect(x: 662, y: 0, width: 188, height: 24)
        #expect(IslandLayout.bubbleDiameter(notch: short) == 20)
        #expect(IslandLayout.bubbleFrame(notch: short, screenSize: screen)
            == CGRect(x: 600, y: 2, width: 20, height: 20))
    }

    @Test func theBubbleHitRectCoversTheSourceBehind() {
        #expect(IslandLayout.bubbleHitRect(notch: notch, screenSize: screen, hasBehind: false)
            == CGRect(x: 588, y: -2, width: 36, height: 36))
        // The source behind shows round(28 × 0.36) = 10 pt further left.
        #expect(IslandLayout.bubbleHitRect(notch: notch, screenSize: screen, hasBehind: true)
            == CGRect(x: 578, y: -2, width: 46, height: 36))
    }

    @Test func theFilesBubbleSitsRightOfTheIslandWithOrWithoutWings() {
        let notch = CGRect(x: 656, y: 0, width: 200, height: 32)
        for wings in [false, true] {
            let island = IslandLayout.frame(
                phase: .collapsed, notch: notch, screenSize: screen, showsWings: wings)
            let bubble = IslandLayout.filesBubbleFrame(
                notch: notch, screenSize: screen, showsWings: wings)
            #expect(bubble.minX == island.maxX + IslandLayout.bubbleGap)
            #expect(bubble.size == CGSize(width: 28, height: 28))
            #expect(bubble.midY == notch.midY)
        }
    }

    @Test func theFilesBubbleHitRectGrowsRightByEachDiscBehind() {
        let notch = CGRect(x: 656, y: 0, width: 200, height: 32)
        let plain = IslandLayout.filesBubbleHitRect(
            notch: notch, screenSize: screen, showsWings: false, behind: 0)
        let two = IslandLayout.filesBubbleHitRect(
            notch: notch, screenSize: screen, showsWings: false, behind: 2)
        #expect(two.minX == plain.minX)
        #expect(two.maxX == plain.maxX + 2 * IslandLayout.bubblePeek(diameter: 28))
    }
}
