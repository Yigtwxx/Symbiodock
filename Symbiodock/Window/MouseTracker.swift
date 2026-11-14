import AppKit

/// Reports the pointer location in AppKit global coordinates.
///
/// The overlay panel ignores mouse events almost everywhere, so tracking areas
/// cannot be used; the pointer has to be observed from outside the window.
@MainActor
final class MouseTracker {
    enum Mode {
        /// Global and local NSEvent monitors. No work while the pointer is still.
        case eventMonitors
        /// Reads the pointer location 30 times per second. Needs no event access.
        case polling
    }

    private let mode: Mode
    private let onMove: @MainActor (CGPoint) -> Void
    private var monitors: [Any] = []
    private var timer: Timer?
    /// Fallback timer used only while the pointer is on the island (`.eventMonitors` mode).
    private var supplementalTimer: Timer?

    init(mode: Mode, onMove: @escaping @MainActor (CGPoint) -> Void) {
        self.mode = mode
        self.onMove = onMove
    }

    func start() {
        switch mode {
        case .eventMonitors:
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }) {
                monitors.append(global)
            }
            // Clicks also re-evaluate the pointer, so a lost exit event cannot outlive a click.
            let localMask = mask.union([.leftMouseDown, .rightMouseDown, .otherMouseDown])
            if let local = NSEvent.addLocalMonitorForEvents(matching: localMask, handler: { [weak self] event in
                MainActor.assumeIsolated { self?.report() }
                return event
            }) {
                monitors.append(local)
            }
        case .polling:
            timer = makePollingTimer()
        }
        report()
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        timer?.invalidate()
        timer = nil
        setSupplementalPolling(false)
    }

    /// Turns the 30 Hz fallback polling on or off. Needed because once the panel accepts
    /// mouse events, the global monitor stops seeing them and local delivery is not guaranteed.
    /// No-op in `.polling` mode, where the timer always runs.
    func setSupplementalPolling(_ enabled: Bool) {
        guard mode == .eventMonitors else { return }
        if enabled {
            guard supplementalTimer == nil else { return }
            supplementalTimer = makePollingTimer()
        } else {
            supplementalTimer?.invalidate()
            supplementalTimer = nil
        }
    }

    /// `.common` mode keeps the timer firing while a menu is open (event tracking mode).
    private func makePollingTimer() -> Timer {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func report() {
        onMove(NSEvent.mouseLocation)
    }
}
