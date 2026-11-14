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

    var body: some View {
        Group {
            if attention == .none {
                EmptyView()
            } else if let frozenAt {
                light(elapsed: frozenAt, moving: true)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !moves)) { context in
                    light(elapsed: context.date.timeIntervalSince(appeared), moving: moves)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { restart() }
        .onChange(of: attention) { restart() }
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

    private func light(elapsed: TimeInterval, moving: Bool) -> some View {
        let color = attention == .needsInput ? AgentPalette.alert : AgentPalette.mint
        let level: Double
        let pass: Double?
        switch attention {
        case .needsInput:
            // Breathes between 35 % and 90 %.
            level = moving ? 0.625 + 0.275 * sin(2 * .pi * elapsed / Self.breathPeriod) : 0.8
            let beat = elapsed.truncatingRemainder(dividingBy: Self.passPeriod)
            pass = moving && beat < Self.passLength ? beat / Self.passLength : nil
        case .finished, .none:
            level = 0.5
            pass = moving && elapsed < Self.passLength ? elapsed / Self.passLength : nil
        }
        return ZStack {
            outline.strokeBorder(color.opacity(level * 0.7), lineWidth: 3).blur(radius: 3)
            outline.strokeBorder(color.opacity(level), lineWidth: 1.5)
            if let pass {
                outline.strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                    .mask { band(at: pass) }
            }
        }
        .mask { Rectangle().padding(edgeInsets) }
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
