import AppKit
import SwiftUI

/// A bar that fills with a measure. Its layers are Core Animation's: when the measure
/// changes, the render server moves the fill and the app does no work per frame
/// (see `LayerAnimation.swift`).
struct MeterBar: NSViewRepresentable {
    /// Seconds the fill takes to reach a new value.
    static let transition: CFTimeInterval = 0.6

    /// 0...1; nil while the measure is unknown: the track alone.
    let fraction: Double?
    /// Left to right.
    let colors: [NSColor]

    func makeNSView(context: Context) -> BarView { BarView() }

    func updateNSView(_ view: BarView, context: Context) {
        view.configure(fraction: fraction, colors: colors)
    }

    final class BarView: NSView {
        private let track = CALayer()
        /// The fill's soft light; a layer of its own, because the fill clips to its bounds.
        private let glow = CALayer()
        private let fill = CAGradientLayer()
        private var fraction: Double?
        private var colors: [NSColor] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            track.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            glow.shadowOffset = .zero
            glow.shadowRadius = 3
            glow.shadowOpacity = 0.55
            fill.startPoint = CGPoint(x: 0, y: 0.5)
            fill.endPoint = CGPoint(x: 1, y: 0.5)
            fill.masksToBounds = true
            for part in [track, glow, fill] {
                part.anchorPoint = CGPoint(x: 0, y: 0.5)
                layer?.addSublayer(part)
            }
            glow.isHidden = true
            fill.isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(fraction: Double?, colors: [NSColor]) {
            if self.colors != colors {
                self.colors = colors
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                fill.colors = colors.map(\.cgColor)
                glow.backgroundColor = colors.last?.cgColor
                glow.shadowColor = colors.last?.cgColor
                CATransaction.commit()
            }
            let clamped = fraction.map { min(1, max(0, $0)) }
            guard clamped != self.fraction else { return }
            // A bar that was empty appears at its value; only a change of value moves.
            let moves = self.fraction != nil && clamped != nil && window != nil
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self.fraction = clamped
            place(animated: moves)
        }

        override func layout() {
            super.layout()
            place(animated: false)
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            let scale = window?.backingScaleFactor ?? 2
            for part in [track, glow, fill] { part.contentsScale = scale }
        }

        private func place(animated: Bool) {
            CATransaction.begin()
            if animated {
                CATransaction.setAnimationDuration(MeterBar.transition)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1))
            } else {
                CATransaction.setDisableActions(true)
            }
            let height = bounds.height
            let origin = CGPoint(x: 0, y: bounds.midY)
            track.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: height)
            track.position = origin
            track.cornerRadius = height / 2
            // Never shorter than it is high: a measure near zero is a dot, not nothing.
            let width = max(bounds.width * (fraction ?? 0), height)
            for part in [glow, fill] {
                part.isHidden = fraction == nil
                part.bounds = CGRect(x: 0, y: 0, width: width, height: height)
                part.position = origin
                part.cornerRadius = height / 2
            }
            CATransaction.commit()
        }
    }
}
