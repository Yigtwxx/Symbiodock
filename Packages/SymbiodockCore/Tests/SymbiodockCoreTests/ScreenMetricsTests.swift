import CoreGraphics
import Testing
@testable import SymbiodockCore

struct ScreenMetricsTests {
    @Test func notchNeedsSafeAreaAndBothAuxiliaryAreas() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let withNotch = ScreenMetrics(
            frame: frame, safeAreaTop: 32,
            auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662)
        let noSafeArea = ScreenMetrics(
            frame: frame, safeAreaTop: 0,
            auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662)
        let noAuxiliary = ScreenMetrics(
            frame: frame, safeAreaTop: 32,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)

        #expect(withNotch.hasNotch)
        #expect(!noSafeArea.hasNotch)
        #expect(!noAuxiliary.hasNotch)
    }

    @Test func localPointFlipsYAndRemovesScreenOrigin() {
        // A second display placed above the primary one.
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 982, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)

        let local = metrics.localPoint(fromGlobal: CGPoint(x: 100, y: 2052))

        #expect(local == CGPoint(x: 100, y: 10))
    }

    @Test func localPointHandlesHorizontalOffset() {
        let metrics = ScreenMetrics(
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)

        let local = metrics.localPoint(fromGlobal: CGPoint(x: 1612, y: 1070))

        #expect(local == CGPoint(x: 100, y: 10))
    }
}
