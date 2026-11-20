import AppKit
import SwiftUI
import SymbiodockCore

/// The working sub-agents of a session, as small dots that circle its working mark, each at
/// its own pace (`AgentSatellites`). One that is new grows in; one that has finished stops,
/// turns mint, swells and goes. Live, each dot rides a layer that Core Animation turns
/// (`Orbits`); still (`frozenAt`, Reduce Motion) SwiftUI draws the dots where they stand.
struct MarkSatellites: View {
    let orbiters: [AgentSatellite]
    let tool: AgentTool
    /// The side of the mark they circle.
    var markSize: CGFloat = 14
    /// Draws the dots where they are this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let dot: CGFloat = 3
    /// Seconds a new dot takes to grow in.
    static let appear: TimeInterval = 0.4
    /// Seconds a finished dot takes to swell and go, and how large it swells.
    static let leave: TimeInterval = 0.9
    static let burst = 2.3

    /// From the mark's centre to a dot's centre: 11 pt for a mark of 14.
    static func radius(markSize: CGFloat) -> CGFloat { markSize * 11 / 14 }

    private var side: CGFloat { 2 * Self.radius(markSize: markSize) + Self.dot }

    var body: some View {
        Group {
            if frozenAt != nil || reduceMotion {
                still
            } else {
                Orbits(
                    orbiters: orbiters, colors: AgentPalette.aurora(for: tool).map { NSColor($0).cgColor },
                    dot: Self.dot)
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var still: some View {
        let radius = Self.radius(markSize: markSize)
        let colors = AgentPalette.aurora(for: tool)
        return ZStack {
            ForEach(Array(orbiters.enumerated()), id: \.element.id) { index, satellite in
                let turn =
                    frozenAt.map { AgentSatellites.turn(of: satellite, at: $0) }
                    ?? AgentSatellites.stillTurn(index: index, count: orbiters.count)
                Circle()
                    .fill(colors.isEmpty ? Color.white : colors[satellite.tone % colors.count])
                    .frame(width: Self.dot, height: Self.dot)
                    .offset(x: radius * sin(2 * .pi * turn), y: -radius * cos(2 * .pi * turn))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: orbiters.map(\.id))
    }
}

/// The live dots. Each rides at the top of a layer as large as the view, and the layer
/// turns about its centre; the render server plays it.
private struct Orbits: NSViewRepresentable {
    let orbiters: [AgentSatellite]
    let colors: [CGColor]
    let dot: CGFloat

    func makeNSView(context: Context) -> OrbitView { OrbitView() }

    func updateNSView(_ view: OrbitView, context: Context) {
        view.configure(orbiters: orbiters, colors: colors, dot: dot)
    }

    static func dismantleNSView(_ view: OrbitView, coordinator: ()) {
        view.stop()
    }

    final class OrbitView: NSView {
        /// The turning layer of each satellite shown, by its id.
        private var carriers: [String: CALayer] = [:]
        private var orbiters: [AgentSatellite] = []
        private var colors: [CGColor] = []
        private var dot: CGFloat = 3

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(orbiters: [AgentSatellite], colors: [CGColor], dot: CGFloat) {
            self.colors = colors
            self.dot = dot
            self.orbiters = orbiters
            let wanted = Set(orbiters.map(\.id))
            // The mark is only there while its session works: a satellite that leaves while
            // the mark stays has finished.
            for id in carriers.keys where !wanted.contains(id) { finish(id) }
            for satellite in orbiters where carriers[satellite.id] == nil { add(satellite) }
            // A dot keeps up with its satellite's tone (a carrier that is finishing is no
            // longer in `carriers` and stays mint).
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for satellite in orbiters {
                carriers[satellite.id]?.sublayers?.first?.backgroundColor = color(for: satellite)
            }
            CATransaction.commit()
        }

        private func color(for satellite: AgentSatellite) -> CGColor {
            colors.isEmpty ? NSColor.white.cgColor : colors[satellite.tone % colors.count]
        }

        /// Takes the motion down: no animation is left.
        func stop() {
            for carrier in carriers.values {
                carrier.removeAllAnimations()
                carrier.sublayers?.forEach { $0.removeAllAnimations() }
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for carrier in carriers.values { place(carrier) }
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stop()
            } else {
                for satellite in orbiters {
                    if let carrier = carriers[satellite.id] { turn(carrier, satellite) }
                }
            }
        }

        /// Sizes a carrier to the view and puts its dot at the top; the layer's y runs up.
        private func place(_ carrier: CALayer) {
            carrier.bounds = CGRect(origin: .zero, size: bounds.size)
            carrier.position = CGPoint(x: bounds.midX, y: bounds.midY)
            carrier.sublayers?.first?.position = CGPoint(x: bounds.width / 2, y: bounds.height - dot / 2)
        }

        private func add(_ satellite: AgentSatellite) {
            let carrier = CALayer()
            let point = CALayer()
            point.backgroundColor = color(for: satellite)
            point.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
            point.cornerRadius = dot / 2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            carrier.addSublayer(point)
            place(carrier)
            // At rest the dot stands at its own starting angle (the layer's y runs up, so a
            // negative angle is clockwise); the orbit animation turns it on from there.
            carrier.transform = CATransform3DMakeRotation(CGFloat(-2 * Double.pi * satellite.phase), 0, 0, 1)
            layer?.addSublayer(carrier)
            CATransaction.commit()
            carriers[satellite.id] = carrier
            turn(carrier, satellite)
            guard window != nil else { return }
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0
            grow.toValue = 1
            grow.duration = MarkSatellites.appear
            grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            point.add(grow, forKey: "appear")
        }

        /// Starts a carrier turning, clockwise as seen: in a layer that is a fall in angle.
        private func turn(_ carrier: CALayer, _ satellite: AgentSatellite) {
            guard window != nil, carrier.animation(forKey: "orbit") == nil else { return }
            let start = -2 * Double.pi * satellite.phase
            let orbit = CABasicAnimation(keyPath: "transform.rotation.z")
            orbit.fromValue = start
            orbit.toValue = start - 2 * Double.pi
            orbit.duration = satellite.period
            orbit.repeatCount = .infinity
            orbit.timingFunction = CAMediaTimingFunction(name: .linear)
            orbit.beginTime = SharedClock.begin(in: carrier)
            orbit.isRemovedOnCompletion = false
            carrier.add(orbit, forKey: "orbit")
        }

        /// A satellite whose sub-agent has finished: it stops where it is, turns mint,
        /// swells and goes.
        private func finish(_ id: String) {
            guard let carrier = carriers.removeValue(forKey: id) else { return }
            guard window != nil, let point = carrier.sublayers?.first else {
                carrier.removeFromSuperlayer()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            carrier.transform = carrier.presentation()?.transform ?? carrier.transform
            carrier.removeAnimation(forKey: "orbit")
            point.backgroundColor = NSColor(AgentPalette.mint).cgColor
            point.opacity = 0
            CATransaction.commit()
            let swell = CAKeyframeAnimation(keyPath: "transform.scale")
            swell.values = [1, MarkSatellites.burst, 0]
            swell.keyTimes = [0, 0.3, 1]
            swell.duration = MarkSatellites.leave
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.3, 1]
            fade.duration = MarkSatellites.leave
            point.add(swell, forKey: "swell")
            point.add(fade, forKey: "fade")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(MarkSatellites.leave))
                carrier.removeFromSuperlayer()
            }
        }
    }
}
