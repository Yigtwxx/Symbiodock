import CoreGraphics
import Testing
@testable import SymbiodockCore

struct NotchGeometryTests {
    @Test func notchDisplayUsesTheGapBetweenAuxiliaryAreas() {
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 662)

        #expect(NotchGeometry.notchRect(for: metrics)
            == CGRect(x: 662, y: 0, width: 188, height: 32))
    }

    @Test func displayWithoutNotchGetsCenteredVirtualNotch() {
        let metrics = ScreenMetrics(
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil)

        #expect(NotchGeometry.notchRect(for: metrics)
            == CGRect(x: 860, y: 0, width: 200, height: 32))
    }
}
