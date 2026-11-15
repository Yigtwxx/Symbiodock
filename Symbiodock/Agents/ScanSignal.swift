import Foundation

/// Lets the session scanner sleep between scans and be woken early. A wake that comes
/// while no one waits is kept for the next wait.
@MainActor
final class ScanSignal {
    private var waiter: CheckedContinuation<Bool, Never>?
    private var pending = false
    /// Tells a wait's timer from the timer of a wait that already ended.
    private var generation = 0

    /// Ends the current wait at once, or the next one if no one waits.
    func fire() {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: true)
        } else {
            pending = true
        }
    }

    /// Waits until `fire()` or until `timeout` has passed. True if it was fired.
    func wait(upTo timeout: Duration) async -> Bool {
        if pending {
            pending = false
            return true
        }
        generation += 1
        let mine = generation
        return await withCheckedContinuation { continuation in
            waiter = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.timeOut(mine)
            }
        }
    }

    private func timeOut(_ wait: Int) {
        guard wait == generation, let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: false)
    }
}
