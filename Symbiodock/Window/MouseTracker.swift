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
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                MainActor.assumeIsolated { self?.report() }
                return event
            }) {
                monitors.append(local)
            }
        case .polling:
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
        }
        report()
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        timer?.invalidate()
        timer = nil
    }

    private func report() {
        onMove(NSEvent.mouseLocation)
    }
}
