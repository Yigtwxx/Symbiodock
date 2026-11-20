import AppKit
import SwiftUI
import SymbiodockCore

/// Four bars that move while something is playing. Decorative: they do not follow the audio.
/// The bars are Core Animation layers that grow and shrink about their centres on repeating
/// animations (`LevelBarsMotion`); the app does no work per frame (see `LayerAnimation.swift`).
struct LevelBars: View {
    let isPlaying: Bool
    /// The cover of what plays: the bars take its colours, left to right. White without one.
    var artwork: Data?

    private static let height: CGFloat = 14
    private static let barWidth: CGFloat = 2.5
    private static let spacing: CGFloat = 2

    var body: some View {
        BarsLayer(
            isPlaying: isPlaying, tint: ArtworkCache.tint(for: artwork), height: Self.height,
            barWidth: Self.barWidth, spacing: Self.spacing
        )
        .frame(
            width: CGFloat(LevelBarsMotion.barCount) * Self.barWidth
                + CGFloat(LevelBarsMotion.barCount - 1) * Self.spacing,
            height: Self.height
        )
        .accessibilityHidden(true)
    }
}

private struct BarsLayer: NSViewRepresentable {
    let isPlaying: Bool
    let tint: ArtworkTint?
    let height: CGFloat
    let barWidth: CGFloat
    let spacing: CGFloat

    func makeNSView(context: Context) -> BarsView { BarsView() }

    func updateNSView(_ view: BarsView, context: Context) {
        view.configure(
            isPlaying: isPlaying, tint: tint, height: height, barWidth: barWidth, spacing: spacing)
    }

    static func dismantleNSView(_ view: BarsView, coordinator: ()) {
        view.stop()
    }

    final class BarsView: NSView {
        private let bars = (0..<LevelBarsMotion.barCount).map { _ in CALayer() }
        private var isPlaying = false
        private var tint: ArtworkTint?
        private var height: CGFloat = 14
        private var barWidth: CGFloat = 2.5
        private var spacing: CGFloat = 2
        private var animatedFor: Bool?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            for bar in bars { layer?.addSublayer(bar) }
            recolor()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(
            isPlaying: Bool, tint: ArtworkTint?, height: CGFloat, barWidth: CGFloat, spacing: CGFloat
        ) {
            if self.tint != tint {
                self.tint = tint
                // Not inside a disabled transaction: a new track's colours fade in.
                recolor()
            }
            if self.height != height || self.barWidth != barWidth || self.spacing != spacing {
                self.height = height
                self.barWidth = barWidth
                self.spacing = spacing
                needsLayout = true
            }
            if self.isPlaying != isPlaying {
                self.isPlaying = isPlaying
                needsLayout = true
            }
            play()
        }

        /// Each bar takes the colour at its place along the cover's run.
        private func recolor() {
            for (index, bar) in bars.enumerated() {
                let position = Double(index) / Double(max(bars.count - 1, 1))
                bar.backgroundColor =
                    tint?.color(at: position).cgColor
                    ?? NSColor.white.withAlphaComponent(0.85).cgColor
            }
        }

        /// Takes the bars down: no animation is left.
        func stop() {
            for bar in bars { bar.removeAllAnimations() }
            animatedFor = nil
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * spacing
            let left = (bounds.width - total) / 2
            for (index, bar) in bars.enumerated() {
                // At rest a bar stands at its resting height; playing, the animation's
                // heights replace it. Bars grow and shrink about their centres.
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height * LevelBarsMotion.restLevel)
                bar.cornerRadius = barWidth / 2
                bar.position = CGPoint(
                    x: left + barWidth / 2 + CGFloat(index) * (barWidth + spacing), y: bounds.midY)
            }
            CATransaction.commit()
            animatedFor = nil
            play()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Off screen the animations have nothing to show; they are added again on return.
                stop()
            } else {
                viewDidChangeBackingProperties()
                play()
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            let scale = window?.backingScaleFactor ?? 2
            for bar in bars { bar.contentsScale = scale }
        }

        /// Playing, each bar gets one repeating animation of its height, on the shared clock so
        /// that every set of bars moves in step. Paused, none is left and the bars stand at rest.
        private func play() {
            guard window != nil, animatedFor != isPlaying else { return }
            animatedFor = isPlaying
            guard isPlaying else {
                for bar in bars { bar.removeAnimation(forKey: "level") }
                return
            }
            for (index, bar) in bars.enumerated() {
                let period = LevelBarsMotion.period(ofBar: index)
                // Sampled from the bar's lowest point, so that the sharp turn of |sin| falls on
                // a sample instead of between two.
                let low = (-LevelBarsMotion.phases[index]).truncatingRemainder(dividingBy: .pi)
                let offset = (low < 0 ? low + .pi : low) / LevelBarsMotion.speeds[index]
                bar.add(
                    CAKeyframeAnimation.repeating(
                        "bounds.size.height", period: period, begin: SharedClock.begin(in: bar)
                    ) { [height] in
                        height * LevelBarsMotion.level(ofBar: index, at: offset + $0)
                    },
                    forKey: "level")
            }
        }
    }
}
