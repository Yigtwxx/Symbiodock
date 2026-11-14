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

    private static let breathPeriod: TimeInterval = 1.8
    private static let passPeriod: TimeInterval = 3.6
    private static let passLength: TimeInterval = 0.9
    private static let dimmestLevel = 0.35
    private static let brightestLevel = 0.9

    var body: some View {
        Group {
            if attention == .none {
                EmptyView()
            } else if let frozenAt {
                light(elapsed: frozenAt)
            } else {
                livingLight
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The light as it lives: nothing here redraws frame by frame. The glow is drawn once;
    /// Core Animation breathes it (`Breathing`) and carries the highlight across the rim
    /// (`RimPass`). With Reduce Motion the glow stands still and nothing passes.
    private var livingLight: some View {
        ZStack {
            if attention == .needsInput, !reduceMotion {
                Breathing(dimmest: Float(Self.dimmestLevel / Self.brightestLevel), period: Self.breathPeriod) {
                    glow(color: AgentPalette.alert, level: Self.brightestLevel)
                }
            } else if attention == .needsInput {
                glow(color: AgentPalette.alert, level: 0.8)
            } else {
                glow(color: AgentPalette.mint, level: 0.5)
            }
            if !reduceMotion {
                // A question that waits sends the highlight across again and again; a
                // session that finishes sends it once. A new state is a new view, so a new
                // state starts a new pass.
                RimPass(
                    isVertical: isVertical, travel: Self.passLength,
                    period: attention == .needsInput ? Self.passPeriod : nil
                ) {
                    highlightStroke
                }
                .id(attention)
            }
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

    /// The whole light `elapsed` seconds after it appeared, drawn still; for renders.
    private func light(elapsed: TimeInterval) -> some View {
        let color = attention == .needsInput ? AgentPalette.alert : AgentPalette.mint
        let level: Double
        let pass: Double?
        switch attention {
        case .needsInput:
            // Breathes between 35 % and 90 %.
            level = 0.625 + 0.275 * sin(2 * .pi * elapsed / Self.breathPeriod)
            pass = Self.pass(elapsed: elapsed, repeating: true)
        case .finished, .none:
            level = 0.5
            pass = Self.pass(elapsed: elapsed, repeating: false)
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

    /// The lit stroke the highlight shows, whole: the band that reveals part of it is added
    /// by `RimPass`, or by `highlightLayer` for a still picture.
    private var highlightStroke: some View {
        outline.strokeBorder(highlight, lineWidth: 1.5)
            .mask { Rectangle().padding(edgeInsets) }
    }

    /// The highlight at one moment, drawn still; for renders.
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
