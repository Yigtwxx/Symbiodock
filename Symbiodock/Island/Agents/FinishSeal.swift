import SwiftUI
import SymbiodockCore

/// A finished session's pet sealed the way Face ID confirms a face: corner brackets close in
/// on the pet, grow into a circle as the pet fades, and the circle turns mint around a
/// check (`AgentSealTiming`). It plays once, from when it appears; `IslandView` settles the
/// session when the seal is over. It redraws only while it moves, never at rest.
struct FinishSeal: View {
    let tool: AgentTool
    let size: CGFloat
    /// Draws the seal at this moment and never moves; for renders.
    var frozenAt: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var drawn = false

    private static let stroke = StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)

    var body: some View {
        Group {
            if let frozenAt {
                seal(AgentSealTiming.pose(at: frozenAt))
            } else if reduceMotion || drawn {
                seal(AgentSealTiming.finalPose)
            } else {
                TimelineView(.animation) { context in
                    seal(AgentSealTiming.pose(at: context.date.timeIntervalSince(start)))
                }
                .task {
                    // Once the check is drawn the seal holds still: stop redrawing.
                    try? await Task.sleep(for: .seconds(AgentSealTiming.checked))
                    drawn = true
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(tool.displayName), finished")
    }

    private func seal(_ pose: AgentSealTiming.Pose) -> some View {
        let side = size * CGFloat(pose.frameScale)
        return ZStack {
            AgentPet(tool: tool, state: .finished, size: size, frozenAt: 0)
                .scaleEffect(pose.petScale)
                .opacity(pose.petOpacity)
            ZStack {
                SealFrame(roundness: pose.roundness)
                    .stroke(.white.opacity(0.9 * (1 - pose.mint)), style: Self.stroke)
                SealFrame(roundness: pose.roundness)
                    .stroke(AgentPalette.mint.opacity(pose.mint), style: Self.stroke)
                CheckShape()
                    .trim(from: 0, to: pose.check)
                    .stroke(AgentPalette.mint, style: Self.stroke)
                    .frame(width: size * 0.42, height: size * 0.42)
            }
            .frame(width: side, height: side)
            .scaleEffect(pose.swell)
        }
    }
}

/// Face ID's frame: at roundness 0 four rounded corner brackets, which lengthen and round
/// until at 1 they are one circle.
private struct SealFrame: Shape {
    var roundness: Double

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let radius = side * CGFloat(0.22 + 0.28 * roundness)
        let outline = Self.outline(square, radius: min(radius, side / 2))
        // The share of each quarter of the outline that is drawn, centred on its corner.
        let share = 0.35 + 0.65 * roundness
        guard share < 0.999 else { return outline }
        var path = Path()
        for corner in 0..<4 {
            let centre = (Double(corner) + 0.5) / 4
            path.addPath(outline.trimmedPath(from: centre - share / 8, to: centre + share / 8))
        }
        return path
    }

    /// A rounded square from the middle of its top edge, clockwise; its corners' midpoints
    /// lie at 1/8, 3/8, 5/8 and 7/8 of its length.
    private static func outline(_ r: CGRect, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: r.midX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        path.addArc(
            center: CGPoint(x: r.maxX - radius, y: r.minY + radius), radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(
            center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius,
            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addArc(
            center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(
            center: CGPoint(x: r.minX + radius, y: r.minY + radius), radius: radius,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
