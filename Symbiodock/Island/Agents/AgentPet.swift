import SwiftUI
import SymbiodockCore

/// A tool's pet: a small field of fine vertical lines in the tool's colour, in which the
/// figure shows as the lines growing brighter and dimmer along their length, the way light
/// falls on a form. It moves with its session: while the session works a wave runs across
/// it from left to right, in depth (each line comes forward, a little larger and brighter,
/// and goes back); while it compacts the wave runs from top to bottom; otherwise it stands
/// still.
struct AgentPet: View {
    let tool: AgentTool
    var state: AgentRowState = .finished
    let size: CGFloat
    /// Draws the pet at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the wave is playing: the pet is then made of layers, not drawn.
    private var waves: Bool {
        frozenAt == nil && (state == .working || state == .compacting) && !reduceMotion
    }

    var body: some View {
        Group {
            if waves {
                // Smooth motion that never rests: Core Animation plays it, the app draws nothing.
                // Like the drawn pet, it reaches past the pet by the most a line can grow.
                AgentPetWave(
                    tool: tool, strength: strength, side: size,
                    direction: state == .compacting ? .down : .across)
                    .frame(
                        width: size * (1 + AgentPetMotion.waveGrowth),
                        height: size * (1 + AgentPetMotion.waveGrowth))
                    .transition(.opacity)
            } else if state == .compacting, let frozenAt {
                downFigure(at: frozenAt)
                    .transition(.opacity)
            } else {
                figure(waveAt: state == .working ? frozenAt : nil)
                    .transition(.opacity)
            }
        }
        // A waving pet's lines stand back a little; fade between the two looks instead of
        // jumping when a session starts or stops working.
        .animation(.easeInOut(duration: 0.35), value: waves)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(tool.displayName)
    }

    /// A pet whose session is doing nothing steps back.
    private var strength: Double {
        switch state {
        case .working, .compacting, .needsInput, .finished: 1
        case .running: 0.7
        case .idle: 0.45
        }
    }

    /// The pet drawn once. With `waveAt` each line is as far forward as the wave has it at
    /// that moment: larger about its centre and in full colour, the others a little
    /// weaker. The canvas reaches past
    /// the pet by the most a line can grow, so that nothing is cut.
    private func figure(waveAt time: TimeInterval?, widened: Bool = false) -> some View {
        let art = AgentPetArt.art(for: tool, strength: strength)
        let lines = art.lines
        let grounds = art.grounds
        let margin = size * AgentPetMotion.waveGrowth / 2
        return Canvas { context, canvas in
            let side = canvas.width - 2 * margin
            let bar = side * AgentPetFigure.barWidth
            let inset = side * AgentPetArt.groundInset
            for (column, stretches) in lines.enumerated() {
                let x = margin + side * AgentPetFigure.pitch * CGFloat(column)
                let forward = time.map { AgentPetMotion.wave(column: column, at: $0) } ?? 0
                // Scaled about the line's own centre, and weaker while it waits for the crest.
                var line = context
                if time != nil {
                    line.opacity = AgentPetMotion.waveRest + (1 - AgentPetMotion.waveRest) * forward
                }
                let scale = 1 + AgentPetMotion.waveGrowth * forward
                let centre = CGPoint(x: x + bar / 2, y: margin + side / 2)
                line.translateBy(x: centre.x, y: centre.y)
                line.scaleBy(x: scale * (widened ? 1 + AgentPetMotion.waveGrowth : 1), y: scale)
                line.translateBy(x: -centre.x, y: -centre.y)
                let whole = CGRect(x: x, y: margin + inset, width: bar, height: side - 2 * inset)
                line.fill(Path(roundedRect: whole, cornerRadius: bar / 2), with: .color(grounds[column]))
                for stretch in stretches {
                    let rect = CGRect(
                        x: x, y: margin + side * stretch.top, width: bar,
                        height: max(side * (stretch.bottom - stretch.top), bar))
                        .intersection(whole)
                    guard !rect.isNull, rect.height > 0 else { continue }
                    line.fill(
                        Path(roundedRect: rect, cornerRadius: bar / 2),
                        with: .linearGradient(
                            stretch.gradient,
                            startPoint: CGPoint(x: x, y: margin + side * stretch.top),
                            endPoint: CGPoint(x: x, y: margin + side * stretch.bottom)))
                }
            }
        }
        .frame(width: size + 2 * margin, height: size + 2 * margin)
    }

    /// A compacting pet at one moment of its downward wave, drawn still; for renders. The
    /// lines stand back, and inside the crest's band they show in full and a touch wider.
    private func downFigure(at time: TimeInterval) -> some View {
        let margin = size * AgentPetMotion.waveGrowth / 2
        return ZStack {
            figure(waveAt: nil).opacity(AgentPetMotion.waveRest)
            if let crest = AgentPetMotion.downCrest(at: time) {
                figure(waveAt: nil, widened: true)
                    .mask {
                        LinearGradient(
                            stops: (0...12).map { step in
                                let distance = abs(Double(step) / 12 - 0.5)
                                return Gradient.Stop(
                                    color: .black.opacity(0.5 * (1 + cos(2 * .pi * distance))),
                                    location: CGFloat(step) / 12)
                            },
                            startPoint: .top, endPoint: .bottom)
                            .frame(height: size * AgentPetMotion.downBand)
                            .position(x: size / 2 + margin, y: margin + size * crest)
                    }
            }
        }
    }
}

/// The pets as they are drawn: for each line, the stretches where the figure is, each with
/// the gradient that carries its light and shade. Worked out once for each tool and
/// strength.
@MainActor
enum AgentPetArt {
    /// How far the ground of a line stops short of the pet's top and bottom, as a fraction
    /// of its side.
    static let groundInset = 0.025

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
