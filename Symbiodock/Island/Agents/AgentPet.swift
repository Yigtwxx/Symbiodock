import SwiftUI
import SymbiodockCore

/// A tool's pet: a small field of fine vertical lines in the tool's colour, in which the
/// figure shows as the lines growing brighter and dimmer along their length, the way light
/// falls on a form. It moves with its session: the lines stir a little while the session
/// works, and it stands still while the session needs input.
struct AgentPet: View {
    let tool: AgentTool
    var state: AgentRowState = .finished
    let size: CGFloat
    /// Draws the pet at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Redrawing more often than every 0.35 s keeps the whole island's update cycle awake,
    /// which costs about 5 % of a core (see `FrameSchedule`). A pet of the collapsed island
    /// (24 pt) stirs by under a point, a step of under a point at this rate; larger pets
    /// only show while the island is open and can afford more.
    private var stirInterval: TimeInterval { size <= 30 ? 0.4 : 1.0 / 12.0 }
    var body: some View {
        Group {
            if let frozenAt {
                figure(time: frozenAt, moving: true)
            } else {
                TimelineView(schedule) { context in
                    figure(time: context.date.timeIntervalSinceReferenceDate, moving: moves)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(tool.displayName)
    }

    /// The pet is redrawn at the stir's pace while it works and never otherwise.
    private var schedule: FrameSchedule {
        FrameSchedule(interval: stirInterval, paused: !moves)
    }

    private var moves: Bool {
        !reduceMotion && state == .working
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
        let art = AgentPetArt.art(for: tool, strength: strength)
        let lines = art.lines
        let grounds = art.grounds
        let stirs = moving && state == .working
        return Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let bar = side * AgentPetFigure.barWidth
            for (column, stretches) in lines.enumerated() {
                let x = side * AgentPetFigure.pitch * CGFloat(column)
                // While its session works, each line is a little longer or shorter.
                let reach = stirs ? AgentPetMotion.sway(column: column, at: time) : 0
                let inset = side * (AgentPetMotion.swayAmplitude - reach)
                let whole = CGRect(x: x, y: inset, width: bar, height: side - 2 * inset)
                context.fill(Path(roundedRect: whole, cornerRadius: bar / 2), with: .color(grounds[column]))
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

    /// Everything about a pet that does not depend on time.
    struct Art {
        let lines: [[Stretch]]
        let grounds: [Color]
    }

    private static var cache: [Key: Art] = [:]

    /// Where a point of the pet lies along its run of colours, which goes from the upper
    /// left (0) to the lower right (1): mostly across, partly down.
    private static func position(ofLine index: Int, down: Double = 0.5) -> Double {
        0.6 * Double(index) / Double(max(AgentPetFigure.lineCount - 1, 1)) + 0.4 * down
    }

    static func art(for tool: AgentTool, strength: Double) -> Art {
        let key = Key(tool: tool, strength: Int((strength * 100).rounded()))
        if let known = cache[key] { return known }
        let art = Art(lines: lines(for: tool, strength: strength), grounds: grounds(for: tool, strength: strength))
        cache[key] = art
        return art
    }

    /// The colour of each line where there is no figure.
    private static func grounds(for tool: AgentTool, strength: Double) -> [Color] {
        (0..<AgentPetFigure.lineCount).map {
            AgentPalette.tint(
                for: tool, strength: strength * AgentPetFigure.groundStrength, across: position(ofLine: $0))
        }
    }

    private static func lines(for tool: AgentTool, strength: Double) -> [[Stretch]] {
        let figure = AgentPetFigure.figure(for: tool)
        let lines = figure.lines.indices.map { index in
            figure.stretches(ofLine: index).map { stretch in
                let last = max(stretch.shades.count - 1, 1)
                let stops = stretch.shades.enumerated().map { position, shade in
                    Gradient.Stop(
                        // A part that glows keeps glowing however far the pet steps back.
                        color: AgentPalette.tint(
                            for: tool, strength: shade > 1 ? 1 + (shade - 1) * strength : strength * shade,
                            across: Self.position(
                                ofLine: index,
                                down: stretch.top + (stretch.bottom - stretch.top) * Double(position) / Double(last))),
                        location: CGFloat(position) / CGFloat(last))
                }
                return Stretch(top: stretch.top, bottom: stretch.bottom, gradient: Gradient(stops: stops))
            }
        }
        return lines
    }
}
