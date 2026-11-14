import Testing
@testable import SymbiodockCore

struct RestartPolicyTests {
    private let short = Duration.seconds(1)

    @Test func backsOffThenGivesUp() {
        var policy = RestartPolicy()
        #expect(policy.delayAfterRun(lasting: short) == .seconds(1))
        #expect(policy.delayAfterRun(lasting: short) == .seconds(2))
        #expect(policy.delayAfterRun(lasting: short) == .seconds(4))
        #expect(policy.delayAfterRun(lasting: short) == nil)
        #expect(policy.delayAfterRun(lasting: short) == nil)
    }

    @Test func longRunResetsTheCount() {
        var policy = RestartPolicy()
        _ = policy.delayAfterRun(lasting: short)
        _ = policy.delayAfterRun(lasting: short)
        _ = policy.delayAfterRun(lasting: short)
        #expect(policy.delayAfterRun(lasting: .seconds(61)) == .seconds(1))
    }

    @Test func longRunAfterTwoShortOnesStartsOver() {
        var policy = RestartPolicy()
        _ = policy.delayAfterRun(lasting: short)
        _ = policy.delayAfterRun(lasting: short)
        #expect(policy.delayAfterRun(lasting: .seconds(120)) == .seconds(1))
        #expect(policy.delayAfterRun(lasting: short) == .seconds(2))
    }

    @Test func exactlyTheStableTimeDoesNotReset() {
        var policy = RestartPolicy()
        _ = policy.delayAfterRun(lasting: short)
        #expect(policy.delayAfterRun(lasting: .seconds(60)) == .seconds(2))
    }

    @Test func zeroMaxRestartsNeverRestarts() {
        var policy = RestartPolicy(maxRestarts: 0)
        #expect(policy.delayAfterRun(lasting: short) == nil)
        #expect(policy.delayAfterRun(lasting: .seconds(120)) == nil)
    }
}
