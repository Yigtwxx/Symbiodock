import SwiftUI
import SymbiodockCore

/// A tool's pet: a small field of fine vertical lines in the tool's colour, in which the
/// figure shows as the lines growing brighter and dimmer along their length, the way light
/// falls on a form. It moves with its session: the lines stir a little while the session
/// works, and the pet hops while the session needs input.
struct AgentPet: View {
    let tool: AgentTool
    var state: AgentRowState = .finished
    let size: CGFloat
    /// Draws the pet at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The stir is slow; it needs no more frames than this.
    private static let frameInterval = 1.0 / 20.0

    var body: some View {
        Group {
            if let frozenAt {
                figure(time: frozenAt, moving: true)
            } else {
                TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !moves)) { context in
                    figure(time: context.date.timeIntervalSinceReferenceDate, moving: moves)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(tool.displayName)
    }

    private var isNeedsInput: Bool {
        if case .needsInput = state { true } else { false }
    }

    private var moves: Bool {
        !reduceMotion && (state == .working || isNeedsInput)
    }

    /// A pet whose session is doing nothing steps back.
    private var strength: Double {
        switch state {
        case .working, .needsInput, .finished: 1
        case .running: 0.7
        case .idle: 0.45
        }
    }

    private func figure(time: TimeInterval, moving: Bool) -> some View {
        let lines = AgentPetArt.lines(for: tool, strength: strength)
        let ground = AgentPalette.tint(for: tool, strength: strength * AgentPetFigure.groundStrength)
        let stirs = moving && state == .working
        let hop = moving && isNeedsInput ? AgentPetMotion.hop(at: time) : 0
        return Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let bar = side * AgentPetFigure.barWidth
            for (column, stretches) in lines.enumerated() {
                let x = side * AgentPetFigure.pitch * CGFloat(column)
                // While its session works, each line is a little longer or shorter.
                let reach = stirs ? AgentPetMotion.sway(column: column, at: time) : 0
                let inset = side * (AgentPetMotion.swayAmplitude - reach)
                let whole = CGRect(x: x, y: inset, width: bar, height: side - 2 * inset)
                context.fill(Path(roundedRect: whole, cornerRadius: bar / 2), with: .color(ground))
                for stretch in stretches {
                    let rect = CGRect(
                        x: x, y: side * stretch.top, width: bar,
                        height: max(side * (stretch.bottom - stretch.top), bar))
                        .intersection(whole)
                    guard !rect.isNull, rect.height > 0 else { continue }
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: bar / 2),
                        with: .linearGradient(
                            stretch.gradient,
                            startPoint: CGPoint(x: x, y: side * stretch.top),
                            endPoint: CGPoint(x: x, y: side * stretch.bottom)))
                }
            }
        }
        .offset(y: -size * hop)
    }
}

/// The pets as they are drawn: for each line, the stretches where the figure is, each with
/// the gradient that carries its light and shade. Worked out once for each tool and
/// strength; a pet is redrawn many times a second while its session works.
@MainActor
private enum AgentPetArt {
    struct Stretch {
        let top: Double
        let bottom: Double
        let gradient: Gradient
    }

    private struct Key: Hashable {
        let tool: AgentTool
        /// Strength in hundredths.
        let strength: Int
    }

    private static var cache: [Key: [[Stretch]]] = [:]

    static func lines(for tool: AgentTool, strength: Double) -> [[Stretch]] {
        let key = Key(tool: tool, strength: Int((strength * 100).rounded()))
        if let known = cache[key] { return known }
        let figure = AgentPetFigure.figure(for: tool)
        let lines = figure.lines.indices.map { index in
            figure.stretches(ofLine: index).map { stretch in
                let last = max(stretch.shades.count - 1, 1)
                let stops = stretch.shades.enumerated().map { position, shade in
                    Gradient.Stop(
                        color: AgentPalette.tint(for: tool, strength: strength * shade),
                        location: CGFloat(position) / CGFloat(last))
                }
                return Stretch(top: stretch.top, bottom: stretch.bottom, gradient: Gradient(stops: stops))
            }
        }
        cache[key] = lines
        return lines
    }
}
