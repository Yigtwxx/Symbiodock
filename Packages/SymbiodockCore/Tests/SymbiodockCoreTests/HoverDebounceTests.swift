import Testing
@testable import SymbiodockCore

struct HoverDebounceTests {
    let t0 = ContinuousClock.now

    private func hovering() -> HoverDebounce<ContinuousClock.Instant> {
        var debounce = HoverDebounce<ContinuousClock.Instant>()
        debounce.reset(to: true)
        return debounce
    }

    @Test func enteringTakesEightyMilliseconds() {
        var debounce = HoverDebounce<ContinuousClock.Instant>()

        #expect(debounce.pointer(inside: true, now: t0) == t0.advanced(by: .milliseconds(80)))
        #expect(debounce.fire(now: t0.advanced(by: .milliseconds(79))) == nil)
        #expect(debounce.fire(now: t0.advanced(by: .milliseconds(80))) == true)
        #expect(debounce.isHovering)
    }

    @Test func leavingTakesAQuarterSecond() {
        var debounce = hovering()
        let t1 = t0.advanced(by: .seconds(5))

        #expect(debounce.pointer(inside: false, now: t1) == t1.advanced(by: .milliseconds(250)))
        #expect(debounce.fire(now: t1.advanced(by: .milliseconds(250))) == false)
        #expect(!debounce.isHovering)
    }

    @Test func aQuickSweepNeverOpens() {
        var debounce = HoverDebounce<ContinuousClock.Instant>()

        _ = debounce.pointer(inside: true, now: t0)
        #expect(debounce.pointer(inside: false, now: t0.advanced(by: .milliseconds(40))) == nil)
        #expect(debounce.fire(now: t0.advanced(by: .milliseconds(200))) == nil)
        #expect(!debounce.isHovering)
    }

    @Test func comingBackBeforeTheExitDelayKeepsItOpen() {
        var debounce = hovering()
        let t1 = t0.advanced(by: .seconds(5))

        _ = debounce.pointer(inside: false, now: t1)
        #expect(debounce.pointer(inside: true, now: t1.advanced(by: .milliseconds(100))) == nil)
        #expect(debounce.fire(now: t1.advanced(by: .milliseconds(300))) == nil)
        #expect(debounce.isHovering)
    }

    @Test func repeatedSamplesKeepTheOriginalDeadline() {
        var debounce = HoverDebounce<ContinuousClock.Instant>()

        _ = debounce.pointer(inside: true, now: t0)
        #expect(
            debounce.pointer(inside: true, now: t0.advanced(by: .milliseconds(50)))
                == t0.advanced(by: .milliseconds(80)))
    }

    @Test func resetDropsThePendingChange() {
        var debounce = HoverDebounce<ContinuousClock.Instant>()

        _ = debounce.pointer(inside: true, now: t0)
        debounce.reset(to: false)
        #expect(debounce.fire(now: t0.advanced(by: .seconds(1))) == nil)
        #expect(!debounce.isHovering)
    }
}
