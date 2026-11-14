import SwiftUI
import SymbiodockCore

/// One glyph for a session's state, used wherever a state is shown. Working turns, needs
/// input knocks, finished draws a check; the rest stand still.
///
/// Nothing here redraws frame by frame: the turning arc, the knocks and the rings are
/// Core Animation layers (`SpinningArc`, `MarkPulses`). SwiftUI draws the still mark, and
/// draws it at one given moment when `frozenAt` is set.
struct AgentStatusMark: View {
    let state: AgentRowState
    var size: CGFloat = 14
    /// Draws the mark at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the mark last became finished, for a second: one ring goes outward from then.
    @State private var finishedAt: Date?

    private static let stroke: CGFloat = 1.75
    private static let turnPeriod: TimeInterval = 1.1

    var body: some View {
        mark
            .frame(width: size, height: size)
            .onChange(of: isFinished) { _, finished in
                guard finished else {
                    finishedAt = nil
                    return
                }
                let stamp = Date()
                finishedAt = stamp
                Task {
                    // The ring is over in under a second; the view that played it goes away.
                    try? await Task.sleep(for: .seconds(1))
                    if finishedAt == stamp { finishedAt = nil }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var isFinished: Bool { state == .finished }

    private var isNeedsInput: Bool {
        if case .needsInput = state { true } else { false }
    }

    private var animates: Bool { !reduceMotion && frozenAt == nil }

    /// Whether Core Animation is turning the arc.
    private var spins: Bool { animates && state == .working }

    /// Whether Core Animation is knocking the dot.
    private var knocks: Bool { animates && isNeedsInput }

    private var color: Color {
        switch state {
        case .working: .white.opacity(0.9)
        case .needsInput: AgentPalette.alert
        case .finished: AgentPalette.mint
        case .running: .white.opacity(0.5)
        case .idle: .white.opacity(0.28)
        }
    }

    private var hasDot: Bool {
        isNeedsInput || state == .running
    }

    /// The mark itself. With a `frozenAt` it is drawn at that moment of its motion; live,
    /// it is the still mark and the layers add the motion.
    private var mark: some View {
        let time = frozenAt
        let turn = time.map { state == .working ? $0.truncatingRemainder(dividingBy: Self.turnPeriod) / Self.turnPeriod * 360 : 0 } ?? 0
        let beat = (time ?? 0).truncatingRemainder(dividingBy: AgentMarkMotion.knockPeriod)
        let frozenKnock = time != nil && isNeedsInput
        return ZStack {
            if frozenKnock {
                ripple(AgentMarkMotion.ripple(atBeat: beat, from: 0))
                ripple(AgentMarkMotion.ripple(atBeat: beat, from: AgentMarkMotion.knockLength))
            }
            if knocks {
                MarkPulses(kind: .knock, color: color, dotSide: dotSide)
                    .transition(.opacity)
            }
            if finishedAt != nil, animates {
                MarkPulses(kind: .ripple, color: color, dotSide: dotSide)
            }
            Circle()
                .trim(from: 0, to: state == .working ? 0.75 : 1)
                .stroke(color, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                .rotationEffect(.degrees(turn - 90))
                .opacity(spins ? 0 : 1)
            if spins {
                SpinningArc(color: color, lineWidth: Self.stroke, period: Self.turnPeriod)
                    .transition(.opacity)
            }
            Circle()
                .fill(color)
                .frame(width: dotSide, height: dotSide)
                .scaleEffect(frozenKnock ? AgentMarkMotion.dotScale(atBeat: beat) : 1)
                .opacity(hasDot && !knocks ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: isFinished ? 1 : 0)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round, lineJoin: .round))
                .padding(size * 0.29)
        }
        .padding(Self.stroke / 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state)
    }

    private var dotSide: CGFloat { size * 0.29 }

    /// A drawn ring that grows to twice the mark's size while it fades; nothing for nil.
    private func ripple(_ progress: Double?) -> some View {
        Circle()
            .stroke(color.opacity(0.6 * (1 - (progress ?? 1))), lineWidth: 1)
            .scaleEffect(1 + (progress ?? 0))
    }

    private var accessibilityText: String {
        switch state {
        case .working: "Working"
        case .needsInput: "Needs input"
        case .finished: "Finished"
        case .running: "Running"
        case .idle: "Idle"
        }
    }
}

/// A check mark filling its rect.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY * 0.92 + rect.minY * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}
