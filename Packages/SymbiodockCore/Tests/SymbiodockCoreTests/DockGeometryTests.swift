import CoreGraphics
import Testing
@testable import SymbiodockCore

@Suite struct DockGeometryTests {
    let screen = CGSize(width: 1728, height: 1117)
    /// Menu bar 34 pt, Dock 66 pt at the bottom.
    let visible = CGRect(x: 0, y: 34, width: 1728, height: 1017)

    @Test func theDockCoversOnlyWhatTheSystemReports() {
        let dock = DockGeometry.obstacle(
            screenSize: screen, visibleFrame: visible,
            reported: CGRect(x: 311, y: 1051, width: 1106, height: 66))
        #expect(dock == DockObstacle(rect: CGRect(x: 311, y: 1051, width: 1106, height: 66), edge: .bottom))
    }

    @Test func withoutAReportTheDockCoversItsWholeEdge() {
        let whole = DockObstacle(rect: CGRect(x: 0, y: 1051, width: 1728, height: 66), edge: .bottom)
        #expect(DockGeometry.obstacle(screenSize: screen, visibleFrame: visible, reported: nil) == whole)
        // A Dock reported on another display says nothing about this one.
        let elsewhere = CGRect(x: 2000, y: 1051, width: 900, height: 66)
        #expect(DockGeometry.obstacle(screenSize: screen, visibleFrame: visible, reported: elsewhere) == whole)
        #expect(DockGeometry.obstacle(screenSize: screen, visibleFrame: visible, reported: .null) == whole)
    }

    @Test func theThicknessComesFromTheVisibleFrame() {
        // A magnified Dock reports a taller bar; the island rests where windows end.
        let dock = DockGeometry.obstacle(
            screenSize: screen, visibleFrame: visible,
            reported: CGRect(x: 311, y: 1020, width: 1106, height: 97))
        #expect(dock?.rect == CGRect(x: 311, y: 1051, width: 1106, height: 66))
    }

    @Test func aHiddenDockIsNoObstacle() {
        let reported = CGRect(x: 311, y: 1051, width: 1106, height: 66)
        let hidden = CGRect(x: 0, y: 34, width: 1728, height: 1083)
        #expect(DockGeometry.obstacle(screenSize: screen, visibleFrame: hidden, reported: reported) == nil)
        let sliver = CGRect(x: 0, y: 34, width: 1728, height: 1079)
        #expect(DockGeometry.obstacle(screenSize: screen, visibleFrame: sliver, reported: reported) == nil)
        #expect(DockGeometry.obstacle(screenSize: screen, visibleFrame: .null, reported: reported) == nil)
        #expect(DockGeometry.obstacle(screenSize: .zero, visibleFrame: visible, reported: reported) == nil)
    }

    @Test func aDockOnTheSideRunsDownItsEdge() {
        let left = DockGeometry.obstacle(
            screenSize: screen, visibleFrame: CGRect(x: 70, y: 34, width: 1658, height: 1083),
            reported: CGRect(x: 0, y: 300, width: 70, height: 500))
        #expect(left == DockObstacle(rect: CGRect(x: 0, y: 300, width: 70, height: 500), edge: .left))

        let right = DockGeometry.obstacle(
            screenSize: screen, visibleFrame: CGRect(x: 0, y: 34, width: 1658, height: 1083),
            reported: nil)
        #expect(right == DockObstacle(rect: CGRect(x: 1658, y: 0, width: 70, height: 1117), edge: .right))
    }

    @Test func aCarriedIslandDocksAgainstTheDockOnlyOverIt() {
        let display = CGRect(origin: .zero, size: screen)
        let dock = DockObstacle(rect: CGRect(x: 311, y: 1051, width: 1106, height: 66), edge: .bottom)
        let onDock = CGRect(x: 0, y: 0, width: 1728, height: 1051)

        #expect(DockGeometry.frame(forCenter: CGPoint(x: 800, y: 900), display: display, dock: dock) == onDock)
        #expect(DockGeometry.frame(forCenter: CGPoint(x: 311, y: 900), display: display, dock: dock) == onDock)
        #expect(DockGeometry.frame(forCenter: CGPoint(x: 200, y: 900), display: display, dock: dock) == display)
        #expect(DockGeometry.frame(forCenter: CGPoint(x: 1600, y: 900), display: display, dock: dock) == display)
        #expect(DockGeometry.frame(forCenter: CGPoint(x: 800, y: 900), display: display, dock: nil) == display)
        #expect(DockGeometry.frame(forCenter: CGPoint(x: CGFloat.nan, y: 900), display: display, dock: dock) == display)
    }

    @Test func trimmingLeavesTheDisplayBesideASideDock() {
        let display = CGRect(origin: .zero, size: screen)
        let left = DockObstacle(rect: CGRect(x: 0, y: 300, width: 70, height: 500), edge: .left)
        #expect(DockGeometry.trimmed(display, by: left) == CGRect(x: 70, y: 0, width: 1658, height: 1117))
        let right = DockObstacle(rect: CGRect(x: 1658, y: 300, width: 70, height: 500), edge: .right)
        #expect(DockGeometry.trimmed(display, by: right) == CGRect(x: 0, y: 0, width: 1658, height: 1117))
        // Centered beside a side Dock's stretch, the island keeps the whole display.
        #expect(DockGeometry.frame(forCenter: CGPoint(x: 40, y: 100), display: display, dock: left) == display)
        #expect(DockGeometry.frame(forCenter: CGPoint(x: 40, y: 500), display: display, dock: left).minX == 70)
    }
}
