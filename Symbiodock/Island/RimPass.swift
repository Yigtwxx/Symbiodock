import AppKit
import SwiftUI

/// SwiftUI content that a soft band of light crosses by itself, run by Core Animation: the
/// rim light's highlight. The content (the lit stroke) is drawn once; a gradient mask
/// slides across it along its long axis, so the stroke shows only where the band is.
///
/// The render server plays the animation and the app does no work per frame (see
/// `LayerAnimation.swift`). A repeating pass begins when the view enters its window and
/// repeats every `period`, resting between passes; a single pass plays once for each view
/// that is made, whatever else happens to it. The mask rests outside the content, so a view
/// whose animation was taken away shows nothing.
struct RimPass<Content: View>: NSViewRepresentable {
    /// The band crosses downward instead of from left to right.
    let isVertical: Bool
    /// Seconds one crossing takes.
    let travel: TimeInterval
    /// Seconds from the start of one crossing to the next; nil for a single crossing.
    let period: TimeInterval?
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> PassView {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.safeAreaRegions = []
        return PassView(host: host)
    }

    func updateNSView(_ view: PassView, context: Context) {
        view.host.rootView = content
        view.configure(isVertical: isVertical, travel: travel, period: period)
    }

    static func dismantleNSView(_ view: PassView, coordinator: ()) {
        view.stop()
    }

    final class PassView: NSView {
        let host: NSHostingView<Content>
        private let band = CAGradientLayer()
        private var isVertical = false
        private var travel: TimeInterval = 1
        private var period: TimeInterval?
        /// When the pass began, on the band's own clock. The animation has to be added again
        /// whenever the island changes size, which it often does just as a session finishes;
        /// starting it from this moment continues the pass instead of dropping it or
        /// starting it over, and a single crossing that is over is not played again.
        private var began: CFTimeInterval?
        private var animatedFor: Key?
        private var placed: Placement?

        private struct Placement: Equatable {
            let size: CGSize
            let isVertical: Bool
        }

        private struct Key: Equatable {
            let size: CGSize
            let isVertical: Bool
            let travel: TimeInterval
            let period: TimeInterval?
        }

        init(host: NSHostingView<Content>) {
            self.host = host
            super.init(frame: .zero)
            wantsLayer = true
            addSubview(host)
            band.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
            band.opacity = 1
            // A mask shows the content only where it has pixels; this one rests off to the
            // side, so nothing shows between passes.
            layer?.mask = band
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(isVertical: Bool, travel: TimeInterval, period: TimeInterval?) {
            guard self.isVertical != isVertical || self.travel != travel || self.period != period else { return }
            self.isVertical = isVertical
            self.travel = travel
            self.period = period
            began = nil
            needsLayout = true
        }

        /// Takes the pass down: no animation is left.
        func stop() {
            band.removeAllAnimations()
            animatedFor = nil
        }

        override func layout() {
            super.layout()
            host.frame = bounds
            let placement = Placement(size: bounds.size, isVertical: isVertical)
            if placement != placed {
                placed = placement
                placeBand()
            }
            play()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Off screen the animation has nothing to show; it is added again on return.
                stop()
            } else {
                play()
            }
        }

        /// The band at rest: just before the start of the axis. The layer's coordinates run
        /// upward from the lower left, so "downward" is toward smaller y.
        private func placeBand() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let length = isVertical ? bounds.height : bounds.width
            let width = max(length * 0.35, 24)
            band.removeAllAnimations()
            animatedFor = nil
            if isVertical {
                band.startPoint = CGPoint(x: 0.5, y: 1)
                band.endPoint = CGPoint(x: 0.5, y: 0)
                band.frame = CGRect(x: 0, y: bounds.height, width: bounds.width, height: width)
            } else {
                band.startPoint = CGPoint(x: 0, y: 0.5)
                band.endPoint = CGPoint(x: 1, y: 0.5)
                band.frame = CGRect(x: -width, y: 0, width: width, height: bounds.height)
            }
            CATransaction.commit()
        }

        private func play() {
            guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
            let key = Key(size: bounds.size, isVertical: isVertical, travel: travel, period: period)
            guard key != animatedFor else { return }
            animatedFor = key
            let now = band.convertTime(CACurrentMediaTime(), from: nil)
            let start = began ?? now
            began = start
            // A single crossing that has already gone by is over.
            if period == nil, now - start >= travel { return }
            let length = isVertical ? bounds.height : bounds.width
            let reach = length + (isVertical ? band.bounds.height : band.bounds.width)
            let keyPath = isVertical ? "transform.translation.y" : "transform.translation.x"
            let distance = isVertical ? -reach : reach
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.calculationMode = .linear
            if let period {
                // Across in `travel`, then out of sight until the next pass.
                animation.values = [0, distance, distance]
                animation.keyTimes = [0, NSNumber(value: travel / period), 1]
                animation.duration = period
                animation.repeatCount = .infinity
                animation.isRemovedOnCompletion = false
            } else {
                animation.values = [0, distance]
                animation.duration = travel
            }
            animation.beginTime = start
            band.add(animation, forKey: "pass")
        }
    }
}
