import SwiftUI
import SymbiodockCore

/// A light along the collapsed island's rim while an agent wants attention. It is drawn
/// inside the island's outline, so the island's frame and hit area stay what they are,
/// and it leaves out the edges that lie against the screen.
struct RimLight: View {
    let attention: AgentAttention
    let radii: IslandCornerRadii
    let dockedEdges: Set<ScreenEdge>
    /// The island is a vertical strip: the highlight travels down instead of across.
    let isVertical: Bool
    /// Draws the light this many seconds after it appeared and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Date()
    /// The finished light has made its one pass and is now still.
    @State private var settled = false

    private static let breathPeriod: TimeInterval = 1.8
    private static let passPeriod: TimeInterval = 3.6
    private static let passLength: TimeInterval = 0.9
    /// The highlight crosses the island in under a second and needs more while it does.
    private static let passInterval: TimeInterval = 1.0 / 30.0

    var body: some View {
        Group {
            if attention == .none {
                EmptyView()
            } else if let frozenAt {
                light(elapsed: frozenAt, moving: true)
            } else if breathes {
                // The breath never rests, so Core Animation plays it; the highlight crosses
                // the rim in under a second and is redrawn only while it does.
                ZStack {
                    Breathing(dimmest: Float(Self.dimmestLevel / Self.brightestLevel), period: Self.breathPeriod) {
                        glow(color: AgentPalette.alert, level: Self.brightestLevel)
                    }
                    TimelineView(passSchedule) { context in
                        highlightLayer(
                            pass: Self.pass(
                                elapsed: context.date.timeIntervalSince(appeared), repeating: true))
                    }
                }
            } else {
                TimelineView(FrameSchedule(interval: Self.passInterval, paused: !moves)) { context in
                    light(elapsed: context.date.timeIntervalSince(appeared), moving: moves)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { restart() }
        .onChange(of: attention) { restart() }
    }

    private static let dimmestLevel = 0.35
    private static let brightestLevel = 0.9

    /// Whether the needs-input light is breathing.
    private var breathes: Bool { attention == .needsInput && !reduceMotion }

    /// The highlight's passes, one every `passPeriod`.
    private var passSchedule: FrameSchedule {
        FrameSchedule(
            interval: Self.passInterval,
            pulse: .init(anchor: appeared, period: Self.passPeriod, length: Self.passLength + 0.05))
    }

    private var moves: Bool {
        !reduceMotion && (attention == .needsInput || (attention == .finished && !settled))
    }

    private func restart() {
        let stamp = Date()
        appeared = stamp
        settled = false
        guard attention == .finished else { return }
        Task {
            try? await Task.sleep(for: .seconds(Self.passLength + 0.1))
            if appeared == stamp { settled = true }
        }
    }

    private var outline: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)
    }

    /// How far the highlight has crossed, 0...1; nil while it is not on its way.
    private static func pass(elapsed: TimeInterval, repeating: Bool) -> Double? {
        let beat = repeating ? elapsed.truncatingRemainder(dividingBy: passPeriod) : elapsed
        return beat >= 0 && beat < passLength ? beat / passLength : nil
    }

    /// The whole light at one moment: the glow, and the highlight if it is on its way.
    private func light(elapsed: TimeInterval, moving: Bool) -> some View {
        let color = attention == .needsInput ? AgentPalette.alert : AgentPalette.mint
        let level: Double
        let pass: Double?
        switch attention {
        case .needsInput:
            // Breathes between 35 % and 90 %.
            level = moving
                ? 0.625 + 0.275 * sin(2 * .pi * elapsed / Self.breathPeriod) : 0.8
            pass = moving ? Self.pass(elapsed: elapsed, repeating: true) : nil
        case .finished, .none:
            level = 0.5
            pass = moving ? Self.pass(elapsed: elapsed, repeating: false) : nil
        }
        return ZStack {
            glow(color: color, level: level)
            highlightLayer(pass: pass)
        }
    }

    /// A glow without a blur: wider strokes under the line, each fainter, which add up to
    /// a soft falloff. Only the first reaches no further in than the edges that are cut.
    private func glow(color: Color, level: Double) -> some View {
        ZStack {
            outline.strokeBorder(color.opacity(level * 0.10), lineWidth: 7)
            outline.strokeBorder(color.opacity(level * 0.16), lineWidth: 5)
            outline.strokeBorder(color.opacity(level * 0.30), lineWidth: 3)
            outline.strokeBorder(color.opacity(level), lineWidth: 1.5)
        }
        .mask { Rectangle().padding(edgeInsets) }
    }

    @ViewBuilder
    private func highlightLayer(pass: Double?) -> some View {
        if let pass {
            outline.strokeBorder(highlight, lineWidth: 1.5)
                .mask { band(at: pass) }
                .mask { Rectangle().padding(edgeInsets) }
        }
    }

    /// `AgentPalette.mint` a third of the way to white.
    private static let brightMint = Color(red: 154.0 / 255.0, green: 239.0 / 255.0, blue: 200.0 / 255.0)

    /// The travelling highlight: nearly white when input is needed, a brightened mint when
    /// the session has finished.
    private var highlight: Color {
        attention == .needsInput ? .white.opacity(0.85) : Self.brightMint
    }

    /// Hides the stroke on the edges that touch the screen: a notch has no line there.
    private var edgeInsets: EdgeInsets {
        EdgeInsets(
            top: dockedEdges.contains(.top) ? 3 : 0,
            leading: dockedEdges.contains(.left) ? 3 : 0,
            bottom: dockedEdges.contains(.bottom) ? 3 : 0,
            trailing: dockedEdges.contains(.right) ? 3 : 0)
    }

    /// A soft band crossing the island along its long axis; `position` runs 0...1.
    private func band(at position: Double) -> some View {
        GeometryReader { proxy in
            let length = isVertical ? proxy.size.height : proxy.size.width
            let width = max(length * 0.35, 24)
            let offset = -width + position * (length + width)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white, .clear],
                        startPoint: isVertical ? .top : .leading,
                        endPoint: isVertical ? .bottom : .trailing))
                .frame(
                    width: isVertical ? proxy.size.width : width,
                    height: isVertical ? width : proxy.size.height)
                .offset(x: isVertical ? 0 : offset, y: isVertical ? offset : 0)
        }
    }
}
