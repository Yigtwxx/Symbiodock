import SwiftUI
import SymbiodockCore

/// One glyph for a session's state, used wherever a state is shown. Working turns, needs
/// input knocks, finished draws a check; the rest stand still.
struct AgentStatusMark: View {
    let state: AgentRowState
    var size: CGFloat = 14
    /// Draws the mark at this moment and never moves; for previews and renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the mark last became finished: one ring goes outward from then.
    @State private var finishedAt: Date?

    private static let stroke: CGFloat = 1.75
    private static let turnPeriod: TimeInterval = 1.1
    private static let knockPeriod: TimeInterval = 2.4
    private static let knockLength: TimeInterval = 0.3
    private static let rippleLength: TimeInterval = 0.9

    var body: some View {
        Group {
            if let frozenAt {
                mark(time: frozenAt, burst: nil, moving: true)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !moves)) { context in
                    mark(
                        time: context.date.timeIntervalSinceReferenceDate,
                        burst: finishedAt.map { context.date.timeIntervalSince($0) },
                        moving: moves)
                }
            }
        }
        .frame(width: size, height: size)
        .onChange(of: isFinished) { _, finished in
            guard finished else {
                finishedAt = nil
                return
            }
            let stamp = Date()
            finishedAt = stamp
            Task {
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

    /// Whether anything is in motion right now.
    private var moves: Bool {
        !reduceMotion && (state == .working || isNeedsInput || finishedAt != nil)
    }

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

    private func mark(time: TimeInterval, burst: TimeInterval?, moving: Bool) -> some View {
        let turn = moving && state == .working
            ? time.truncatingRemainder(dividingBy: Self.turnPeriod) / Self.turnPeriod * 360 : 0
        let beat = time.truncatingRemainder(dividingBy: Self.knockPeriod)
        let knocking = moving && isNeedsInput
        return ZStack {
            ripple(knocking ? Self.progress(beat, from: 0) : burst.flatMap { Self.progress($0, from: 0) })
            ripple(knocking ? Self.progress(beat, from: Self.knockLength) : nil)
            Circle()
                .trim(from: 0, to: state == .working ? 0.75 : 1)
                .stroke(color, style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                .rotationEffect(.degrees(turn - 90))
            Circle()
                .fill(color)
                .frame(width: size * 0.29, height: size * 0.29)
                .scaleEffect(knocking ? Self.knockScale(beat) : 1)
                .opacity(hasDot ? 1 : 0)
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

    /// A ring that grows to twice the mark's size while it fades; nothing for nil.
    private func ripple(_ progress: Double?) -> some View {
        Circle()
            .stroke(color.opacity(0.6 * (1 - (progress ?? 1))), lineWidth: 1)
            .scaleEffect(1 + (progress ?? 0))
    }

    /// 0...1 through a ripple that started at `start` seconds into the beat; nil outside it.
    private static func progress(_ beat: TimeInterval, from start: TimeInterval) -> Double? {
        let value = (beat - start) / rippleLength
        return value >= 0 && value < 1 ? value : nil
    }

    /// Two knocks at the start of every beat, then rest.
    private static func knockScale(_ beat: TimeInterval) -> CGFloat {
        guard beat < 2 * knockLength else { return 1 }
        let local = beat.truncatingRemainder(dividingBy: knockLength) / knockLength
        return 1 + 0.35 * sin(.pi * local)
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
