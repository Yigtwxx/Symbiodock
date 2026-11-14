import AppKit
import SwiftUI
import SymbiodockCore

/// The status mark's pulses as Core Animation layers: for "needs input" the centre dot
/// that knocks twice with a ring sent out by each knock, repeating every beat; for
/// "finished" one ring that goes out once. The ring grows to twice the mark's size while
/// it fades (see `AgentMarkMotion`). The view fills the circle's frame and the rings
/// overflow it, as the drawn rings did.
///
/// The layers are built once; the render server plays the animations and the app does no
/// work per frame (see `LayerAnimation.swift`). A repeating animation is anchored to the
/// shared clock, so every mark knocks in step. The one-shot ring plays once for each view
/// that is made, whatever else happens to the view, and then rests. Layers rest invisible
/// (rings) or at their own size (dot), so a view whose animations were taken away shows
/// the still mark.
struct MarkPulses: NSViewRepresentable {
    enum Kind { case knock, ripple }

    let kind: Kind
    /// The mark's colour at full strength.
    let color: Color
    /// The centre dot's diameter, for `.knock`.
    let dotSide: CGFloat

    func makeNSView(context: Context) -> PulseView { PulseView(kind: kind) }

    func updateNSView(_ view: PulseView, context: Context) {
        view.configure(ring: NSColor(color.opacity(0.6)), dot: NSColor(color), dotSide: dotSide)
    }

    static func dismantleNSView(_ view: PulseView, coordinator: ()) {
        view.stop()
    }

    final class PulseView: NSView {
        private let kind: Kind
        private let rings = [CAShapeLayer(), CAShapeLayer()]
        private let dot = CALayer()
        private var dotSide: CGFloat = 4
        /// The one-shot ring has been started; it is never started again.
        private var played = false
        /// What the animations on the layers were built for.
        private var animatedFor: Key?

        private struct Key: Equatable {
            let size: CGSize
            let dotSide: CGFloat
        }

        init(kind: Kind) {
            self.kind = kind
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = false
            for ring in rings {
                ring.fillColor = nil
                ring.lineWidth = 1
                ring.opacity = 0
                layer?.addSublayer(ring)
            }
            dot.opacity = kind == .knock ? 1 : 0
            layer?.addSublayer(dot)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(ring: NSColor, dot color: NSColor, dotSide: CGFloat) {
            // Set at once: a layer would otherwise fade a colour in over a quarter second.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in rings { layer.strokeColor = ring.cgColor }
            dot.backgroundColor = color.cgColor
            CATransaction.commit()
            if self.dotSide != dotSide {
                self.dotSide = dotSide
                needsLayout = true
            }
        }

        /// Takes the pulses down: no animation is left.
        func stop() {
            for layer in rings { layer.removeAllAnimations() }
            dot.removeAllAnimations()
            animatedFor = nil
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let side = min(bounds.width, bounds.height)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            for ring in rings {
                ring.frame = bounds
                ring.path = CGPath(
                    ellipseIn: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
                    transform: nil)
            }
            dot.bounds = CGRect(x: 0, y: 0, width: dotSide, height: dotSide)
            dot.cornerRadius = dotSide / 2
            dot.position = center
            CATransaction.commit()
            play()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Off screen the animations have nothing to show; they are added again on return.
                for layer in rings { layer.removeAllAnimations() }
                dot.removeAllAnimations()
                animatedFor = nil
            } else {
                viewDidChangeBackingProperties()
                play()
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            let scale = window?.backingScaleFactor ?? 2
            for layer in rings { layer.contentsScale = scale }
            dot.contentsScale = scale
        }

        private func play() {
            guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
            let key = Key(size: bounds.size, dotSide: dotSide)
            guard key != animatedFor else { return }
            animatedFor = key
            switch kind {
            case .knock: knock()
            case .ripple: ripple()
            }
        }

        /// Two knocks and a ring for each, every beat, on the shared clock.
        private func knock() {
            let period = AgentMarkMotion.knockPeriod
            let begin = SharedClock.begin(in: dot)
            dot.add(
                CAKeyframeAnimation.repeating("transform.scale", period: period, begin: begin) {
                    AgentMarkMotion.dotScale(atBeat: $0)
                },
                forKey: "knock")
            for (ring, start) in zip(rings, [0, AgentMarkMotion.knockLength]) {
                ring.add(
                    CAKeyframeAnimation.repeating("transform.scale", period: period, begin: begin) {
                        1 + (AgentMarkMotion.ripple(atBeat: $0, from: start) ?? 0)
                    },
                    forKey: "ringOut")
                ring.add(
                    CAKeyframeAnimation.repeating("opacity", period: period, begin: begin) {
                        // Hidden at the instant a ring leaves; the next sample is nearly full.
                        guard let progress = AgentMarkMotion.ripple(atBeat: $0, from: start), progress > 0 else {
                            return 0
                        }
                        return 1 - progress
                    },
                    forKey: "ringFade")
            }
        }

        /// One ring, once. The layer's own values are its rest, so it is gone afterwards.
        private func ripple() {
            guard !played else { return }
            played = true
            let ring = rings[0]
            let out = CABasicAnimation(keyPath: "transform.scale")
            out.fromValue = 1
            out.toValue = 2
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            for animation in [out, fade] {
                animation.duration = AgentMarkMotion.rippleLength
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
            }
            ring.add(out, forKey: "ringOut")
            ring.add(fade, forKey: "ringFade")
        }
    }
}
