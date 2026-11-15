import AppKit
import SwiftUI
import SymbiodockCore

/// A working pet: its lines as Core Animation layers, each coming forward and going back on
/// its own repeating animations so that a crest runs across the pet from left to right, in
/// depth (see `AgentPetMotion.wave`): a line at the crest is larger and shows in full; the
/// others stand back a little. The view is larger than the pet by the most a line can grow,
/// so a line at the crest is never cut.
/// The layers are built once; the render server plays the animations and the app does no
/// work per frame (see `LayerAnimation.swift` for why that matters). At rest the pet looks as the
/// still `Canvas` drawing does. Nothing moves up or down.
/// With `direction: .down` (a compacting session) the lines stand back and a band runs down
/// the pet instead, inside which they show in full and a touch wider.
struct AgentPetWave: NSViewRepresentable {
    let tool: AgentTool
    /// How strongly the pet shows its colour, 0...1.
    let strength: Double
    /// The side of the pet in points.
    let side: CGFloat

    /// Which way the crest runs: across from left to right (working), or down from top to
    /// bottom (compacting).
    enum Direction: Equatable {
        case across, down
    }

    var direction: Direction = .across

    func makeNSView(context: Context) -> WaveView { WaveView() }

    func updateNSView(_ view: WaveView, context: Context) {
        view.configure(tool: tool, strength: strength, side: side, direction: direction)
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
            let direction: Direction
        }

        /// How finely one period of the wave is sampled into keyframes: 120 a second.
        private static let samples = Int(AgentPetMotion.wavePeriod * 120)
        /// A whole number of periods, so a start time of zero (which Core Animation reads as
        /// "now") can be moved without moving the phase.
        private static let phaseShift = -1000 * AgentPetMotion.wavePeriod

        private var spec: Spec?
        private var built: Spec?
        private var columns: [CALayer] = []
        private var band: CAGradientLayer?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(tool: AgentTool, strength: Double, side: CGFloat, direction: Direction) {
            spec = Spec(
                tool: tool, strength: strength, side: side, scale: window?.backingScaleFactor ?? 2,
                direction: direction)
            rebuildIfNeeded()
        }

        /// Takes the pet down: no layer and no animation is left.
        func stop() {
            for layer in columns { layer.removeAllAnimations() }
            layer?.sublayers = nil
            columns = []
            band?.removeAllAnimations()
            band = nil
            built = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Off screen the animations have nothing to show; they are added again on return.
                for layer in columns { layer.removeAnimation(forKey: "wave"); layer.removeAnimation(forKey: "waveDepth") }
                band?.removeAnimation(forKey: "band")
            } else {
                // The scale is only known once the view is in a window.
                if let current = spec, let scale = window?.backingScaleFactor, scale != current.scale {
                    spec = Spec(
                        tool: current.tool, strength: current.strength, side: current.side, scale: scale,
                        direction: current.direction)
                }
                rebuildIfNeeded()
                animate()
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            guard var current = spec, let scale = window?.backingScaleFactor else { return }
            current = Spec(
                tool: current.tool, strength: current.strength, side: current.side, scale: scale,
                direction: current.direction)
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
            for layer in columns { layer.removeAllAnimations() }
            band?.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.sublayers = nil
            columns = []
            band = nil

            let art = AgentPetArt.art(for: spec.tool, strength: spec.strength)
            for index in art.lines.indices {
                let line = makeLine(index, art: art, spec: spec)
                // Waiting for the crest a line stands back; the wave brings it forward.
                line.opacity = Float(AgentPetMotion.waveRest)
                root.addSublayer(line)
                columns.append(line)
            }
            if spec.direction == .down {
                root.addSublayer(makeCrest(art: art, spec: spec))
            }
            CATransaction.commit()
        }

        /// One line of the pet: its ground and the stretches where the figure is. Layer
        /// coordinates run upward from the lower left.
        private func makeLine(_ index: Int, art: AgentPetArt.Art, spec: Spec) -> CALayer {
            let side = spec.side
            let bar = side * AgentPetFigure.barWidth
            let inset = side * AgentPetArt.groundInset
            // Room around the pet for a line at the crest, as in the drawn pet.
            let margin = side * AgentPetMotion.waveGrowth / 2
            let line = CALayer()
            line.frame = CGRect(
                x: margin + side * AgentPetFigure.pitch * CGFloat(index), y: margin, width: bar, height: side)
            line.contentsScale = spec.scale

            let ground = CALayer()
            ground.frame = CGRect(x: 0, y: inset, width: bar, height: side - 2 * inset)
            ground.cornerRadius = bar / 2
            ground.backgroundColor = NSColor(art.grounds[index]).cgColor
            line.addSublayer(ground)

            for stretch in art.lines[index] {
                // In the top-left coordinates the `Canvas` draws in.
                let nominalTop = side * stretch.top
                let nominalBottom = side * stretch.bottom
                let top = max(nominalTop, inset)
                let bottom = min(max(nominalBottom, nominalTop + bar), side - inset)
                guard bottom > top else { continue }
                let paint = CAGradientLayer()
                paint.frame = CGRect(x: 0, y: side - bottom, width: bar, height: bottom - top)
                paint.cornerRadius = bar / 2
                let colors = stretch.gradient.stops.map { NSColor($0.color).cgColor }
                if colors.count >= 2 {
                    paint.colors = colors
                    paint.locations = stretch.gradient.stops.map { NSNumber(value: Double($0.location)) }
                } else {
                    // A gradient layer needs two colours; one colour is a plain fill.
                    paint.backgroundColor = colors.first
                }
                // The colours run from the stretch's own ends, which the layer may overshoot.
                paint.startPoint = CGPoint(x: 0.5, y: 1 - (nominalTop - top) / (bottom - top))
                paint.endPoint = CGPoint(x: 0.5, y: 1 - (nominalBottom - top) / (bottom - top))
                paint.contentsScale = spec.scale
                line.addSublayer(paint)
            }
            return line
        }

        /// The downward crest: the same lines in full colour and a touch wider, seen only
        /// through a soft band that runs down the pet (`animateBand`).
        private func makeCrest(art: AgentPetArt.Art, spec: Spec) -> CALayer {
            let whole = spec.side * (1 + AgentPetMotion.waveGrowth)
            let crest = CALayer()
            crest.frame = CGRect(x: 0, y: 0, width: whole, height: whole)
            for index in art.lines.indices {
                let line = makeLine(index, art: art, spec: spec)
                line.transform = CATransform3DMakeScale(1 + AgentPetMotion.waveGrowth, 1, 1)
                crest.addSublayer(line)
            }
            let mask = CAGradientLayer()
            mask.bounds = CGRect(x: 0, y: 0, width: whole, height: spec.side * AgentPetMotion.downBand)
            mask.position = CGPoint(
                x: whole / 2, y: Self.bandY(AgentPetMotion.downCrestRange.lowerBound, spec: spec))
            // A raised cosine across the band, as the crest across has.
            let steps = 12
            mask.colors = (0...steps).map { step in
                let distance = abs(Double(step) / Double(steps) - 0.5)
                return NSColor.black.withAlphaComponent(0.5 * (1 + cos(2 * .pi * distance))).cgColor
            }
            mask.locations = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
            crest.mask = mask
            band = mask
            return crest
        }

        /// The band's centre in layer coordinates for a crest at `fraction` of the pet's
        /// height from its top.
        private static func bandY(_ fraction: Double, spec: Spec) -> CGFloat {
            let margin = spec.side * AgentPetMotion.waveGrowth / 2
            return margin + spec.side * CGFloat(1 - fraction)
        }

        /// Gives each line its animations, replacing any it has. All of them start from the
        /// same fixed moment of the media clock, so the crest is whole, two pets wave in step
        /// and a pet that returns picks the wave up where it is.
        private func animate() {
            guard window != nil, let spec = built else { return }
            let begin = (columns.first?.convertTime(0, from: nil) ?? 0) + Self.phaseShift
            switch spec.direction {
            case .across:
                for (column, line) in columns.enumerated() {
                    let forward = (0...Self.samples).map { step -> Double in
                        let time = AgentPetMotion.wavePeriod * Double(step % Self.samples) / Double(Self.samples)
                        return AgentPetMotion.wave(column: column, at: time)
                    }
                    line.add(
                        animation("transform.scale", forward.map { 1 + AgentPetMotion.waveGrowth * $0 }, begin: begin),
                        forKey: "wave")
                    let rest = AgentPetMotion.waveRest
                    line.add(
                        animation("opacity", forward.map { rest + (1 - rest) * $0 }, begin: begin),
                        forKey: "waveDepth")
                }
            case .down:
                animateBand(spec: spec, begin: begin)
            }
        }

        /// Runs the band down the pet at the crest's even pace (`AgentPetMotion.downCrest`),
        /// then straight back above it to wait. The two keyframes at the same moment make the
        /// jump, so the band never sweeps back up across the pet.
        private func animateBand(spec: Spec, begin: CFTimeInterval) {
            guard let band else { return }
            let entry = Double(Self.bandY(AgentPetMotion.downCrestRange.lowerBound, spec: spec))
            let exit = Double(Self.bandY(AgentPetMotion.downCrestRange.upperBound, spec: spec))
            let end = NSNumber(value: AgentPetMotion.waveTravel / AgentPetMotion.wavePeriod)
            let run = CAKeyframeAnimation(keyPath: "position.y")
            run.values = [entry, exit, entry, entry]
            run.keyTimes = [0, end, end, 1]
            run.calculationMode = .linear
            run.duration = AgentPetMotion.wavePeriod
            run.repeatCount = .infinity
            run.beginTime = begin
            run.isRemovedOnCompletion = false
            band.add(run, forKey: "band")
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
