import AppKit
import SwiftUI
import SymbiodockCore

/// The light of a working agent (`WorkingAurora`): colours that flow along the island's
/// free long edge, just outside it, as a fine line and a glow that breathes. The view fills
/// the band beside that edge. Live, Core Animation plays it (`AuroraFlow`) and the app does
/// no work per frame (see `LayerAnimation.swift`); still (`frozenAt`, Reduce Motion) SwiftUI
/// draws one moment, once.
struct WorkingAuroraLight: View {
    let tool: AgentTool
    /// The island's edge the band lies against.
    let edge: ScreenEdge
    /// The session has finished and its seal plays; the light turns mint with it.
    var isFinishing = false
    /// Draws the light as it is this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let frozenAt {
                AuroraStill(
                    colors: colors, edge: edge, flow: WorkingAurora.flow(at: frozenAt),
                    glow: WorkingAurora.glowOpacity(at: frozenAt), stretch: WorkingAurora.stretch(at: frozenAt))
            } else if reduceMotion {
                AuroraStill(colors: colors, edge: edge, flow: 0, glow: WorkingAurora.stillGlow, stretch: 1)
            } else {
                AuroraFlow(
                    colors: AgentPalette.aurora(for: tool).map { NSColor($0).cgColor },
                    finishColors: AgentPalette.auroraFinish.map { NSColor($0).cgColor },
                    edge: edge, isFinishing: isFinishing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var colors: [Color] { isFinishing ? AgentPalette.auroraFinish : AgentPalette.aurora(for: tool) }

    /// The colours as they lie along twice the edge: two whole runs that end where they
    /// began, so that a slide of one edge's length brings them back to the start.
    static func run<C>(_ colors: [C]) -> [C] { colors + colors + [colors[0]] }
}

/// One moment of the light, drawn once. It is drawn as if the edge ran along the top with
/// the light going down, and the context is turned to the edge it is for.
private struct AuroraStill: View {
    let colors: [Color]
    let edge: ScreenEdge
    /// How far the colours have travelled, a share of one run.
    let flow: Double
    let glow: Double
    let stretch: Double

    var body: some View {
        Canvas { context, size in
            let isSide = edge == .left || edge == .right
            let length = isSide ? size.height : size.width
            context.concatenate(Self.placing(edge: edge, in: size))
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: WorkingAuroraLight.run(colors)),
                startPoint: CGPoint(x: (flow - 1) * length, y: 0),
                endPoint: CGPoint(x: (flow + 1) * length, y: 0))
            draw(
                shading, in: WorkingAurora.glowRect(length: length, stretch: stretch), fallsOff: true,
                opacity: glow, context: context)
            draw(
                shading, in: WorkingAurora.lineRect(length: length), fallsOff: false, opacity: 1,
                context: context)
        }
    }

    /// Fills `rect` with the colours, fading in at both ends and, for the glow, fading out
    /// away from the edge.
    private func draw(
        _ shading: GraphicsContext.Shading, in rect: CGRect, fallsOff: Bool, opacity: Double,
        context: GraphicsContext
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        var layer = context
        layer.opacity = opacity
        let ends = WorkingAurora.endLocations(length: rect.width)
        layer.clipToLayer { mask in
            mask.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: ends[0]), .init(color: .white, location: ends[1]),
                        .init(color: .white, location: ends[2]), .init(color: .clear, location: ends[3]),
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        }
        if fallsOff {
            layer.clipToLayer { mask in
                mask.fill(
                    Path(rect),
                    with: .linearGradient(
                        Gradient(stops: WorkingAurora.falloff.map {
                            .init(color: .white.opacity($0.strength), location: $0.place)
                        }),
                        startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            }
        }
        layer.fill(Path(rect), with: shading)
    }

    /// Maps the band as drawn (x along the edge, y out from it, y running down) onto a band
    /// of `size` beside `edge`. The colours run left to right, and top to bottom on a side.
    private static func placing(edge: ScreenEdge, in size: CGSize) -> CGAffineTransform {
        switch edge {
        case .bottom: .identity
        case .top: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        case .left: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0)
        case .right: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        }
    }
}

/// The live light. A sheet of the colours, twice the edge long, slides by one edge's length
/// again and again; it shows through a mask of a fine line and a glow, and the glow's
/// strength and reach rise and fall. The render server plays all of it.
private struct AuroraFlow: NSViewRepresentable {
    let colors: [CGColor]
    let finishColors: [CGColor]
    let edge: ScreenEdge
    let isFinishing: Bool

    func makeNSView(context: Context) -> FlowView { FlowView() }

    func updateNSView(_ view: FlowView, context: Context) {
        view.configure(colors: colors, finishColors: finishColors, edge: edge, isFinishing: isFinishing)
    }

    static func dismantleNSView(_ view: FlowView, coordinator: ()) {
        view.stop()
    }

    final class FlowView: NSView {
        /// The band as it is laid out: x along the edge, y out from it, y running up as in
        /// every layer. Its transform turns it to the edge it is for.
        private let band = CALayer()
        /// What shows: the colours, through `shape`.
        private let sheet = CALayer()
        private let run = CAGradientLayer()
        private let shape = CALayer()
        private let glow = CAGradientLayer()
        private let glowEnds = CAGradientLayer()
        private let line = CAGradientLayer()
        private var edge: ScreenEdge = .bottom
        /// The edge's length the animations were made for.
        private var playedLength: CGFloat = 0
        /// The colours the sheet has, or is on its way to, so that a repeated configure with
        /// the same inputs adds nothing.
        private var target: Target?

        private enum Target: Equatable {
            case tool([CGColor])
            case mint
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            run.startPoint = CGPoint(x: 0, y: 0.5)
            run.endPoint = CGPoint(x: 1, y: 0.5)
            run.anchorPoint = .zero
            // Strongest at the edge (the bottom of the band as laid out), nothing at its reach.
            glow.colors = WorkingAurora.falloff.map { NSColor.white.withAlphaComponent($0.strength).cgColor }
            glow.locations = WorkingAurora.falloff.map { NSNumber(value: $0.place) }
            glow.startPoint = CGPoint(x: 0.5, y: 0)
            glow.endPoint = CGPoint(x: 0.5, y: 1)
            // It stretches away from the edge, which stays where it is.
            glow.anchorPoint = CGPoint(x: 0.5, y: 0)
            for ends in [glowEnds, line] {
                ends.colors = [NSColor.clear.cgColor, NSColor.white.cgColor, NSColor.white.cgColor, NSColor.clear.cgColor]
                ends.startPoint = CGPoint(x: 0, y: 0.5)
                ends.endPoint = CGPoint(x: 1, y: 0.5)
            }
            glow.mask = glowEnds
            shape.addSublayer(glow)
            shape.addSublayer(line)
            sheet.masksToBounds = true
            sheet.addSublayer(run)
            sheet.mask = shape
            band.addSublayer(sheet)
            layer?.addSublayer(band)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(colors: [CGColor], finishColors: [CGColor], edge: ScreenEdge, isFinishing: Bool) {
            let wanted: Target = isFinishing ? .mint : .tool(colors)
            if wanted != target {
                let toolRun = WorkingAuroraLight.run(colors)
                if target == nil {
                    // Born in the tool's colours; a seal that already plays turns them mint below.
                    setRun(toolRun)
                    target = .tool(colors)
                }
                if wanted != target { turn(to: isFinishing ? WorkingAuroraLight.run(finishColors) : toolRun, finishing: isFinishing) }
                target = wanted
            }
            if self.edge != edge {
                self.edge = edge
                needsLayout = true
            }
            play()
        }

        /// Fades the sheet to `colors` from what shows now. Turning mint waits for the moment
        /// the seal's frame does and takes as long; going back is quick and starts at once.
        private func turn(to colors: [CGColor], finishing: Bool) {
            let from = run.presentation()?.colors ?? run.colors
            setRun(colors)
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = from
            animation.toValue = colors
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if finishing {
                animation.beginTime = run.convertTime(CACurrentMediaTime(), from: nil) + WorkingAurora.finishTintDelay
                animation.duration = WorkingAurora.finishTintDuration
                // The old colours hold until it begins.
                animation.fillMode = .backwards
            } else {
                animation.duration = WorkingAurora.tintBack
            }
            run.add(animation, forKey: "tint")
        }

        private func setRun(_ colors: [CGColor]?) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            run.colors = colors
            CATransaction.commit()
        }

        /// Takes the light down: no animation is left.
        func stop() {
            run.removeAllAnimations()
            glow.removeAllAnimations()
            playedLength = 0
        }

        override func layout() {
            super.layout()
            let isSide = edge == .left || edge == .right
            let length = isSide ? bounds.height : bounds.width
            let depth = isSide ? bounds.width : bounds.height
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            band.bounds = CGRect(x: 0, y: 0, width: length, height: depth)
            band.position = CGPoint(x: bounds.midX, y: bounds.midY)
            band.setAffineTransform(Self.turn(to: edge))
            sheet.frame = band.bounds
            shape.frame = band.bounds
            run.bounds = CGRect(x: 0, y: 0, width: 2 * length, height: depth)
            run.position = CGPoint(x: -length, y: 0)
            let glowSize = WorkingAurora.glowRect(length: length, stretch: 1)
            glow.bounds = CGRect(x: 0, y: 0, width: glowSize.width, height: glowSize.height)
            glow.position = CGPoint(x: length / 2, y: 0)
            glowEnds.frame = glow.bounds
            glowEnds.locations = WorkingAurora.endLocations(length: glowSize.width).map { NSNumber(value: $0) }
            let lineRect = WorkingAurora.lineRect(length: length)
            line.frame = lineRect
            line.locations = WorkingAurora.endLocations(length: lineRect.width).map { NSNumber(value: $0) }
            CATransaction.commit()
            play()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                // Off screen the animations have nothing to show; they are added again on return.
                stop()
            } else {
                play()
            }
        }

        private func play() {
            let length = band.bounds.width
            guard window != nil, length > 0 else { return }
            // The slide is as long as the edge: a new length needs a new slide.
            if playedLength != length {
                playedLength = length
                let slide = CABasicAnimation(keyPath: "position.x")
                slide.fromValue = -length
                slide.toValue = 0
                slide.duration = WorkingAurora.flowPeriod
                slide.repeatCount = .infinity
                slide.timingFunction = CAMediaTimingFunction(name: .linear)
                slide.beginTime = SharedClock.begin(in: run)
                slide.isRemovedOnCompletion = false
                run.add(slide, forKey: "flow")
            }
            guard glow.animation(forKey: "breath") == nil else { return }
            let begin = SharedClock.begin(in: glow)
            glow.add(
                CAKeyframeAnimation.repeating(
                    "opacity", period: WorkingAurora.breathPeriod, begin: begin, value: WorkingAurora.glowOpacity),
                forKey: "breath")
            glow.add(
                CAKeyframeAnimation.repeating(
                    "transform.scale.y", period: WorkingAurora.breathPeriod, begin: begin, value: WorkingAurora.stretch),
                forKey: "stretch")
        }

        /// Turns the band as laid out (edge along its bottom, light going up, colours
        /// running to the right) to `edge`, about its centre. The view's y runs up.
        private static func turn(to edge: ScreenEdge) -> CGAffineTransform {
            switch edge {
            // The island is above the band: the edge is the band's top, the light goes down.
            case .bottom: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
            case .top: .identity
            // The island is right of the band: light to the left, colours running down.
            case .left: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 0, ty: 0)
            // The island is left of the band: light to the right, colours running down.
            case .right: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)
            }
        }
    }
}
