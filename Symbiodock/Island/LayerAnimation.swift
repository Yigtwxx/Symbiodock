import AppKit
import SwiftUI

// Motion run by Core Animation. The render server plays these; the app does no work per
// frame.
//
// Why nothing in the island redraws frame by frame: measured on the always-on island, while
// any SwiftUI view in the full-screen panel redraws more often than about every 0.35 s,
// SwiftUI keeps the panel's update cycle running at the screen's rate, and that alone costs
// about 5 % of a core, whatever the view draws (an empty `Canvas` costs the same). So every
// motion that repeats or has to be smooth is a layer animation, and SwiftUI draws a view
// only when its content changes.

/// One fixed moment on the media clock. Repeating animations that start from it keep one
/// phase: views that play the same motion move in step, and a view that returns to its
/// window picks the motion up where it is. It is long past, so it is never "now", which
/// Core Animation reads a begin time of 0 as.
enum SharedClock {
    static let base: CFTimeInterval = 1

    /// `base` in the time of `layer`'s own space.
    @MainActor
    static func begin(in layer: CALayer) -> CFTimeInterval {
        layer.convertTime(base, from: nil)
    }
}

extension CAKeyframeAnimation {
    /// A repeating animation of `keyPath` through `value` sampled over one `period`: 120
    /// samples a second, joined by straight lines, from the fixed `begin` time.
    static func repeating(
        _ keyPath: String, period: TimeInterval, begin: CFTimeInterval, value: (TimeInterval) -> Double
    ) -> CAKeyframeAnimation {
        let samples = max(8, Int((period * 120).rounded()))
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0...samples).map { value(period * Double($0) / Double(samples)) }
        animation.keyTimes = (0...samples).map { NSNumber(value: Double($0) / Double(samples)) }
        animation.calculationMode = .linear
        animation.duration = period
        animation.repeatCount = .infinity
        animation.beginTime = begin
        animation.isRemovedOnCompletion = false
        return animation
    }
}

/// An arc that turns about its centre: the status mark's working spinner. It fills its
/// frame the way a SwiftUI `Circle` does and starts at 12 o'clock, going clockwise.
struct SpinningArc: NSViewRepresentable {
    let color: Color
    /// Colours the arc shows instead of `color`, from the upper left to the lower right.
    /// They stand still and the arc turns over them, so it changes colour as it goes.
    var gradient: [Color]? = nil
    let lineWidth: CGFloat
    /// Seconds for one turn.
    let period: TimeInterval
    /// The share of the circle that is drawn.
    var sweep: Double = 0.75
    /// Draws the arc as this many dashes with equal gaps; nil for a solid arc.
    var dashCount: Int? = nil

    func makeNSView(context: Context) -> ArcView { ArcView() }

    func updateNSView(_ view: ArcView, context: Context) {
        view.configure(
            color: NSColor(color), gradient: gradient?.map { NSColor($0).cgColor }, lineWidth: lineWidth,
            period: period, sweep: sweep, dashCount: dashCount)
    }

    final class ArcView: NSView {
        private let arc = CAShapeLayer()
        private let tint = CAGradientLayer()
        /// Whether the arc is the mask of `tint` instead of a line of its own.
        private var isTinted = false
        private var period: TimeInterval = 1
        private var sweep = 0.75
        private var dashCount: Int?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            arc.fillColor = nil
            arc.lineCap = .round
            // The layer's coordinates run upward: the upper left is (0, 1).
            tint.startPoint = CGPoint(x: 0, y: 1)
            tint.endPoint = CGPoint(x: 1, y: 0)
            layer?.addSublayer(arc)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(
            color: NSColor, gradient: [CGColor]?, lineWidth: CGFloat, period: TimeInterval, sweep: Double,
            dashCount: Int?
        ) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.lineWidth = lineWidth
            if let gradient {
                // The mask only says where the colours show.
                arc.strokeColor = NSColor.white.cgColor
                tint.colors = gradient
            } else {
                arc.strokeColor = color.cgColor
            }
            if isTinted != (gradient != nil) {
                isTinted = gradient != nil
                arc.removeFromSuperlayer()
                tint.removeFromSuperlayer()
                tint.mask = nil
                if isTinted {
                    tint.mask = arc
                    layer?.addSublayer(tint)
                } else {
                    layer?.addSublayer(arc)
                }
                needsLayout = true
            }
            CATransaction.commit()
            if self.period != period || self.sweep != sweep || self.dashCount != dashCount {
                self.period = period
                self.sweep = sweep
                self.dashCount = dashCount
                needsLayout = true
            }
            startSpinning()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // The line reaches half its width past the circle; the colours have to cover it.
            let reach = arc.lineWidth
            tint.frame = bounds.insetBy(dx: -reach, dy: -reach)
            arc.frame = isTinted ? CGRect(x: reach, y: reach, width: bounds.width, height: bounds.height) : bounds
            let radius = min(bounds.width, bounds.height) / 2
            let path = CGMutablePath()
            // In the layer's own coordinates y points up, so clockwise runs to smaller angles.
            path.addArc(
                center: CGPoint(x: bounds.width / 2, y: bounds.height / 2), radius: radius,
                startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * sweep, clockwise: true)
            arc.path = path
            if let dashCount, dashCount > 0 {
                let piece = 2 * .pi * radius / CGFloat(2 * dashCount)
                arc.lineDashPattern = [NSNumber(value: Double(piece)), NSNumber(value: Double(piece))]
            } else {
                arc.lineDashPattern = nil
            }
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
