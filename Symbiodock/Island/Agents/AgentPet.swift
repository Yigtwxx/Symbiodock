import SwiftUI
import SymbiodockCore

/// A tool's pet: its figure drawn from seven vertical bars with round ends, in the tool's
/// colour. It moves with its session: a wave runs through it while the session works, and
/// it hops while the session needs input.
struct AgentPet: View {
    let tool: AgentTool
    var state: AgentRowState = .finished
    let size: CGFloat
    /// Draws the pet at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let frozenAt {
                figure(time: frozenAt, moving: true)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !moves)) { context in
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
        let glyph = AgentPetGlyph.glyph(for: tool)
        let waves = moving && state == .working
        let hop = moving && isNeedsInput ? AgentPetMotion.hop(at: time) : 0
        let color = AgentPalette.tint(for: tool).opacity(strength)
        return Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let bar = side * AgentPetGlyph.barWidth
            for (column, segments) in glyph.columns.enumerated() {
                // Only the figure's upper outline moves; it stands on what is below.
                let rise = waves ? AgentPetMotion.sway(column: column, at: time) : 0
                for (index, segment) in segments.enumerated() {
                    let top = max(index == 0 ? segment.top - rise : segment.top, 0)
                    let rect = CGRect(
                        x: side * AgentPetGlyph.pitch * CGFloat(column),
                        y: side * top,
                        width: bar,
                        height: max(side * (segment.bottom - top), bar))
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: bar / 2), with: .color(color))
                }
            }
        }
        .offset(y: -size * hop)
    }
}
