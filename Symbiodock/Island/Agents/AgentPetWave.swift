import AppKit
import SwiftUI
import SymbiodockCore

/// A working pet: its lines as Core Animation layers, each coming forward and going back on
/// its own repeating animations so that a crest runs across the pet from left to right, in
/// depth (see `AgentPetMotion.wave`): a line at the crest is larger and lit towards white.
/// The layers are built once; the render server plays the animations and the app does no
/// work per frame (see `FrameSchedule` for why that matters). At rest the pet looks as the
/// still `Canvas` drawing does. Nothing moves up or down.
struct AgentPetWave: NSViewRepresentable {
    let tool: AgentTool
    /// How strongly the pet shows its colour, 0...1.
    let strength: Double
    /// The side of the pet in points.
    let side: CGFloat

    func makeNSView(context: Context) -> WaveView { WaveView() }

    func updateNSView(_ view: WaveView, context: Context) {
        view.configure(tool: tool, strength: strength, side: side)
    }

    static func dismantleNSView(_ view: WaveView, coordinator: ()) {
        view.stop()
    }

    final class WaveView: NSView {
        private struct Spec: Equatable {
            let tool: AgentTool
            let strength: Double
            let side: CGFloat
            let scale: CGFloat
        }

        /// How finely one period of the wave is sampled into keyframes: 120 a second.
        private static let samples = Int(AgentPetMotion.wavePeriod * 120)
        /// A whole number of periods, so a start time of zero (which Core Animation reads as
        /// "now") can be moved without moving the phase.
        private static let phaseShift = -1000 * AgentPetMotion.wavePeriod

        private var spec: Spec?
        private var built: Spec?
        private var columns: [CALayer] = []
        /// The white copy of each line's shape that is faded in to light the line.
        private var glows: [CALayer] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(tool: AgentTool, strength: Double, side: CGFloat) {
            spec = Spec(tool: tool, strength: strength, side: side, scale: window?.backingScaleFactor ?? 2)
            rebuildIfNeeded()
        }

        /// Takes the pet down: no layer and no animation is left.
        func stop() {
            for layer in columns + glows { layer.removeAllAnimations() }
            layer?.sublayers = nil
            columns = []
            glows = []
            built = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Off screen the animations have nothing to show; they are added again on return.
                for layer in columns + glows { layer.removeAnimation(forKey: "wave") }
            } else {
                rebuildIfNeeded()
                animate()
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            guard var current = spec, let scale = window?.backingScaleFactor else { return }
            current = Spec(tool: current.tool, strength: current.strength, side: current.side, scale: scale)
            spec = current
            rebuildIfNeeded()
        }

        private func rebuildIfNeeded() {
            guard let spec, spec != built else { return }
            build(spec)
            built = spec
            animate()
        }

        /// One layer for each line, holding the line's ground and the stretches where the
        /// figure is. Layer coordinates run upward from the lower left.
        private func build(_ spec: Spec) {
            guard let root = layer else { return }
            for layer in columns + glows { layer.removeAllAnimations() }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.sublayers = nil
            columns = []
            glows = []

            let art = AgentPetArt.art(for: spec.tool, strength: spec.strength)
            let side = spec.side
            let bar = side * AgentPetFigure.barWidth
            let inset = side * AgentPetArt.groundInset
            for (index, stretches) in art.lines.enumerated() {
                let line = CALayer()
                line.frame = CGRect(x: side * AgentPetFigure.pitch * CGFloat(index), y: 0, width: bar, height: side)
                line.contentsScale = spec.scale

                let ground = CALayer()
                ground.frame = CGRect(x: 0, y: inset, width: bar, height: side - 2 * inset)
                ground.cornerRadius = bar / 2
                ground.backgroundColor = NSColor(art.grounds[index]).cgColor
                line.addSublayer(ground)

                for stretch in stretches {
                    // In the top-left coordinates the `Canvas` draws in.
                    let nominalTop = side * stretch.top
                    let nominalBottom = side * stretch.bottom
                    let top = max(nominalTop, inset)
                    let bottom = min(max(nominalBottom, nominalTop + bar), side - inset)
                    guard bottom > top else { continue }
                    let paint = CAGradientLayer()
                    paint.frame = CGRect(x: 0, y: side - bottom, width: bar, height: bottom - top)
                    paint.cornerRadius = bar / 2
                    paint.colors = stretch.gradient.stops.map { NSColor($0.color).cgColor }
                    paint.locations = stretch.gradient.stops.map { NSNumber(value: Double($0.location)) }
                    // The colours run from the stretch's own ends, which the layer may overshoot.
                    paint.startPoint = CGPoint(x: 0.5, y: 1 - (nominalTop - top) / (bottom - top))
                    paint.endPoint = CGPoint(x: 0.5, y: 1 - (nominalBottom - top) / (bottom - top))
                    paint.contentsScale = spec.scale
                    line.addSublayer(paint)
                }
                // The line's shape in white, over everything on it; the wave fades it in.
                let glow = CALayer()
                glow.frame = ground.frame
                glow.cornerRadius = bar / 2
                glow.backgroundColor = NSColor.white.cgColor
                glow.opacity = 0
                line.addSublayer(glow)
                root.addSublayer(line)
                columns.append(line)
                glows.append(glow)
            }
            CATransaction.commit()
        }

        /// Gives each line its animations, replacing any it has. All of them start from the
        /// same fixed moment of the media clock, so the crest is whole, two pets wave in step
        /// and a pet that returns picks the wave up where it is.
        private func animate() {
            guard window != nil else { return }
            let begin = (columns.first?.convertTime(0, from: nil) ?? 0) + Self.phaseShift
            for (column, line) in columns.enumerated() {
                let forward = (0...Self.samples).map { step -> Double in
                    let time = AgentPetMotion.wavePeriod * Double(step % Self.samples) / Double(Self.samples)
                    return AgentPetMotion.wave(column: column, at: time)
                }
                line.add(
                    animation("transform.scale", forward.map { 1 + AgentPetMotion.waveGrowth * $0 }, begin: begin),
                    forKey: "wave")
                glows[column].add(
                    animation("opacity", forward.map { AgentPetMotion.waveGlow * $0 }, begin: begin),
                    forKey: "wave")
            }
        }

        private func animation(_ keyPath: String, _ values: [Double], begin: CFTimeInterval) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = (0...Self.samples).map { NSNumber(value: Double($0) / Double(Self.samples)) }
            animation.calculationMode = .linear
            animation.duration = AgentPetMotion.wavePeriod
            animation.repeatCount = .infinity
            animation.beginTime = begin
            animation.isRemovedOnCompletion = false
            return animation
        }
    }
}
