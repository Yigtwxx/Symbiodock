import AppKit
import SwiftUI
import SymbiodockCore

/// The light that greets a new track: a line in the cover's colours, drawn from the middle of
/// the rim out to both ends, lit whole for a moment, then fading (`TrackGlowMotion`). It lies
/// inside the outline it follows. Live it plays once, by Core Animation (`GlowPass`); a view
/// is made for each light and removed when it is over. Still (`frozenAt`, for renders)
/// SwiftUI draws one moment of it.
struct TrackGlowLine: View {
    enum Outline: Equatable {
        /// The collapsed island's rim, less the edges against the screen.
        case island(radii: IslandCornerRadii, dockedEdges: Set<ScreenEdge>)
        /// The bubble beside the island, from its top round both sides.
        case bubble

        /// The line in `bounds`, wholly inside the outline; origin top left, y down.
        @MainActor
        func path(in bounds: CGRect) -> CGPath {
            let inset = TrackGlowLine.lineWidth / 2
            let rect = bounds.insetBy(dx: inset, dy: inset)
            switch self {
            case .island(let radii, let dockedEdges):
                func inner(_ radius: CGFloat) -> CGFloat { max(radius - inset, 0) }
                return TrackGlowOutline.island(
                    in: rect,
                    radii: IslandCornerRadii(
                        topLeading: inner(radii.topLeading), topTrailing: inner(radii.topTrailing),
                        bottomLeading: inner(radii.bottomLeading),
                        bottomTrailing: inner(radii.bottomTrailing)),
                    dockedEdges: dockedEdges)
            case .bubble:
                return TrackGlowOutline.bubble(in: rect)
            }
        }
    }

    let outline: Outline
    /// The colours of the cover of the track; nil for none, and the line is white.
    let tint: ArtworkTint?
    /// The island is a vertical strip: the colours run bottom to top, like its bars.
    var isVertical = false
    /// Draws the light as it is this many seconds in and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let lineWidth: CGFloat = 1.5
    /// The halos under the line and the line itself: how wide, and how strong.
    static let strokes: [(width: CGFloat, strength: Double)] = [(6, 0.12), (3.5, 0.30), (lineWidth, 1)]
    /// How strong the white line of a cover without colour is.
    private static let colourlessStrength = 0.85

    var body: some View {
        Group {
            if let frozenAt {
                still(at: frozenAt)
            } else {
                GlowPass(outline: outline, colors: layerColors, isVertical: isVertical, spreads: !reduceMotion)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// At least two colours, for a gradient layer.
    private var layerColors: [CGColor] {
        guard let tint, let first = tint.stops.first else {
            let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Self.colourlessStrength)
            return [white, white]
        }
        return tint.stops.count > 1 ? tint.stops.map(\.cgColor) : [first.cgColor, first.cgColor]
    }

    private var fill: AnyShapeStyle {
        guard let tint, !tint.stops.isEmpty else {
            return AnyShapeStyle(Color.white.opacity(Self.colourlessStrength))
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: tint.stops.map(\.color),
                startPoint: isVertical ? .bottom : .leading,
                endPoint: isVertical ? .top : .trailing))
    }

    /// One moment of the light, drawn still. Like the live one it is the colours across the
    /// whole frame, shown through the stroked lines; a gradient on the stroke itself would
    /// squeeze the whole run into however much of the line is drawn.
    private func still(at time: TimeInterval) -> some View {
        let reach = reduceMotion ? 1 : TrackGlowMotion.reach(at: time)
        let strength = reduceMotion ? TrackGlowMotion.stillOpacity(at: time) : TrackGlowMotion.opacity(at: time)
        return GeometryReader { proxy in
            let line = Path(outline.path(in: CGRect(origin: .zero, size: proxy.size)))
                .trimmedPath(from: 0.5 - reach / 2, to: 0.5 + reach / 2)
            Rectangle()
                .fill(fill)
                .mask {
                    ZStack {
                        ForEach(Self.strokes.indices, id: \.self) { index in
                            line.stroke(
                                Color.white.opacity(Self.strokes[index].strength),
                                style: StrokeStyle(lineWidth: Self.strokes[index].width, lineCap: .round))
                        }
                    }
                }
        }
        .opacity(strength)
    }
}

/// The live light: a gradient in the cover's colours, shown through a mask of stroked lines
/// whose two ends Core Animation moves apart from the middle, and whose opacity it then
/// lowers to nothing. The render server plays it; the app does no work per frame (see
/// `LayerAnimation.swift`). It plays once for each view that is made: when the island changes
/// size the line follows, and the light goes on from where it was.
private struct GlowPass: NSViewRepresentable {
    let outline: TrackGlowLine.Outline
    let colors: [CGColor]
    let isVertical: Bool
    /// False with Reduce Motion: the whole line rises and fades, and nothing travels.
    let spreads: Bool

    func makeNSView(context: Context) -> PassView { PassView() }

    func updateNSView(_ view: PassView, context: Context) {
        view.configure(outline: outline, colors: colors, isVertical: isVertical, spreads: spreads)
    }

    static func dismantleNSView(_ view: PassView, coordinator: ()) {
        view.stop()
    }

    final class PassView: NSView {
        private let gradient = CAGradientLayer()
        private let mask = CALayer()
        private let lines: [CAShapeLayer]
        private var outline: TrackGlowLine.Outline?
        private var spreads = true
        /// When the light began, on the gradient's own clock. The animations are added again
        /// when the view returns to its window; starting them from this moment continues
        /// the light instead of starting it over, and a light that is over is not played
        /// again.
        private var began: CFTimeInterval?
        private var isPlaying = false

        override init(frame: NSRect) {
            lines = TrackGlowLine.strokes.map { stroke in
                let line = CAShapeLayer()
                line.fillColor = nil
                line.strokeColor = NSColor.white.withAlphaComponent(stroke.strength).cgColor
                line.lineWidth = stroke.width
                line.lineCap = .round
                return line
            }
            super.init(frame: frame)
            wantsLayer = true
            lines.forEach(mask.addSublayer)
            gradient.mask = mask
            // At rest nothing shows: the light is only its animation.
            gradient.opacity = 0
            layer?.addSublayer(gradient)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(outline: TrackGlowLine.Outline, colors: [CGColor], isVertical: Bool, spreads: Bool) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // A cover that arrives while the light plays changes its colours at once.
            gradient.colors = colors
            // The layer's coordinates run upward from the lower left.
            gradient.startPoint = isVertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
            gradient.endPoint = isVertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
            CATransaction.commit()
            if self.outline != outline {
                self.outline = outline
                needsLayout = true
            }
            if self.spreads != spreads {
                self.spreads = spreads
                stop()
            }
            play()
        }

        /// Takes the light down: no animation is left.
        func stop() {
            gradient.removeAllAnimations()
            lines.forEach { $0.removeAllAnimations() }
            isPlaying = false
        }

        override func layout() {
            super.layout()
            guard let outline else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.frame = bounds
            mask.frame = bounds
            // The outline is made with y running down; the layers' y runs up.
            var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
            let path = outline.path(in: bounds).copy(using: &flip)
            for line in lines {
                line.frame = bounds
                line.path = path
            }
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

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            let scale = window?.backingScaleFactor ?? 2
            lines.forEach { $0.contentsScale = scale }
        }

        private func play() {
            guard window != nil, outline != nil, !isPlaying else { return }
            isPlaying = true
            let now = gradient.convertTime(CACurrentMediaTime(), from: nil)
            let start = began ?? now
            began = start
            // A light that has already gone by is over.
            guard now - start < TrackGlowMotion.duration else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Between the middle and itself there is no line; without the spread it is whole.
            for line in lines {
                line.strokeStart = spreads ? 0.5 : 0
                line.strokeEnd = spreads ? 0.5 : 1
            }
            CATransaction.commit()

            let strength = Self.sampled("opacity", spreads ? TrackGlowMotion.opacity : TrackGlowMotion.stillOpacity)
            strength.beginTime = start
            gradient.add(strength, forKey: "strength")
            guard spreads else { return }
            let from = Self.sampled("strokeStart") { 0.5 * (1 - TrackGlowMotion.reach(at: $0)) }
            let to = Self.sampled("strokeEnd") { 0.5 * (1 + TrackGlowMotion.reach(at: $0)) }
            from.beginTime = start
            to.beginTime = start
            // The line stays whole while the light fades, then the layer's own values (no
            // line) hold, under an opacity of nothing.
            for line in lines {
                line.add(from, forKey: "from")
                line.add(to, forKey: "to")
            }
        }

        /// An animation of `keyPath` through `value` over the light's whole length: 60
        /// samples a second, joined by straight lines.
        private static func sampled(_ keyPath: String, _ value: (TimeInterval) -> Double) -> CAKeyframeAnimation {
            let duration = TrackGlowMotion.duration
            let samples = max(8, Int((duration * 60).rounded()))
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = (0...samples).map { value(duration * Double($0) / Double(samples)) }
            animation.keyTimes = (0...samples).map { NSNumber(value: Double($0) / Double(samples)) }
            animation.calculationMode = .linear
            animation.duration = duration
            return animation
        }
    }
}
