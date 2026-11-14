import AppKit
import SwiftUI

// Motion that must be smooth and never rests, run by Core Animation. The render server
// plays these; the app does no work per frame (see `FrameSchedule` for why that matters).

/// An arc that turns about its centre: the status mark's working spinner. It fills its
/// frame the way a SwiftUI `Circle` does and starts at 12 o'clock, going clockwise.
struct SpinningArc: NSViewRepresentable {
    let color: Color
    let lineWidth: CGFloat
    /// Seconds for one turn.
    let period: TimeInterval
    /// The share of the circle that is drawn.
    var sweep: Double = 0.75

    func makeNSView(context: Context) -> ArcView { ArcView() }

    func updateNSView(_ view: ArcView, context: Context) {
        view.configure(color: NSColor(color), lineWidth: lineWidth, period: period, sweep: sweep)
    }

    final class ArcView: NSView {
        private let arc = CAShapeLayer()
        private var period: TimeInterval = 1
        private var sweep = 0.75

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            arc.fillColor = nil
            arc.lineCap = .round
            layer?.addSublayer(arc)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(color: NSColor, lineWidth: CGFloat, period: TimeInterval, sweep: Double) {
            arc.strokeColor = color.cgColor
            arc.lineWidth = lineWidth
            if self.period != period || self.sweep != sweep {
                self.period = period
                self.sweep = sweep
                needsLayout = true
            }
            startSpinning()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.frame = bounds
            let radius = min(bounds.width, bounds.height) / 2
            let path = CGMutablePath()
            // In the layer's own coordinates y points up, so clockwise runs to smaller angles.
            path.addArc(
                center: CGPoint(x: bounds.width / 2, y: bounds.height / 2), radius: radius,
                startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * sweep, clockwise: true)
            arc.path = path
            CATransaction.commit()
            startSpinning()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            startSpinning()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            arc.contentsScale = window?.backingScaleFactor ?? 2
        }

        private func startSpinning() {
            guard window != nil else { return }
            if let known = arc.animation(forKey: "spin") as? CABasicAnimation, known.duration == period {
                return
            }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = period
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spin.isRemovedOnCompletion = false
            arc.add(spin, forKey: "spin")
        }
    }
}

/// SwiftUI content whose opacity rises and falls by itself, run by Core Animation:
/// the rim light's breath. The content is drawn once, at its brightest.
struct Breathing<Content: View>: NSViewRepresentable {
    /// The opacity at the dimmest point, 0...1 of the content's own.
    let dimmest: Float
    /// Seconds for a whole breath, in and out.
    let period: TimeInterval
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> Host {
        let host = Host(rootView: content)
        host.sizingOptions = []
        host.safeAreaRegions = []
        return host
    }

    func updateNSView(_ host: Host, context: Context) {
        host.rootView = content
        host.configure(dimmest: dimmest, period: period)
    }

    final class Host: NSHostingView<Content> {
        private var dimmest: Float = 1
        private var period: TimeInterval = 1

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(dimmest: Float, period: TimeInterval) {
            let changed = self.dimmest != dimmest || self.period != period
            self.dimmest = dimmest
            self.period = period
            startBreathing(replacing: changed)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            startBreathing(replacing: false)
        }

        private func startBreathing(replacing: Bool) {
            guard window != nil, let layer else { return }
            if replacing { layer.removeAnimation(forKey: "breath") }
            if layer.animation(forKey: "breath") != nil { return }
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = 1.0
            breath.toValue = dimmest
            breath.duration = period / 2
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breath.isRemovedOnCompletion = false
            layer.add(breath, forKey: "breath")
        }
    }
}
