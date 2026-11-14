import SwiftUI
import SymbiodockCore

/// A tool's pet: its figure drawn from fine vertical lines with round ends, in the tool's
/// colour. Parts of the figure that stand farther back are drawn weaker, which gives it
/// depth. It moves with its session: its lines stir a little while the session works, and
/// it hops while the session needs input.
struct AgentPet: View {
    let tool: AgentTool
    var state: AgentRowState = .finished
    let size: CGFloat
    /// Draws the pet at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How strongly a line is drawn in front, in the middle and at the back.
    private static let depthStrength: [Double] = [1, 0.5, 0.26]
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
        let glyph = AgentPetGlyph.glyph(for: tool)
        let stirs = moving && state == .working
        let hop = moving && isNeedsInput ? AgentPetMotion.hop(at: time) : 0
        let tool = tool
        let strength = strength
        return Canvas { context, canvas in
            let side = min(canvas.width, canvas.height)
            let bar = side * AgentPetGlyph.barWidth
            // Back to front, so a nearer stretch covers the end of a farther one it touches.
            for depth in Self.depthStrength.indices.reversed() {
                let color = AgentPalette.tint(for: tool, strength: strength * Self.depthStrength[depth])
                for (column, segments) in glyph.columns.enumerated() {
                    let rise = stirs ? AgentPetMotion.sway(column: column, at: time) : 0
                    for (index, segment) in segments.enumerated() where segment.depth == depth {
                        var top = segment.top
                        var bottom = segment.bottom
                        if index == 0 {
                            // Only the top of a line moves; the figure stands on the rest.
                            top = min(max(top - rise, 0), bottom - AgentPetGlyph.barWidth)
                        } else if segments[index - 1].bottom == segment.top,
                                  segments[index - 1].depth < depth {
                            // Runs on under the nearer stretch above it, so no notch shows.
                            top -= AgentPetGlyph.barWidth
                        }
                        if index + 1 < segments.count, segments[index + 1].top == segment.bottom,
                           segments[index + 1].depth < depth {
                            bottom += AgentPetGlyph.barWidth
                        }
                        let rect = CGRect(
                            x: side * AgentPetGlyph.pitch * CGFloat(column),
                            y: side * top,
                            width: bar,
                            height: max(side * (bottom - top), bar))
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: bar / 2), with: .color(color))
                    }
                }
            }
        }
        .offset(y: -size * hop)
    }
}
