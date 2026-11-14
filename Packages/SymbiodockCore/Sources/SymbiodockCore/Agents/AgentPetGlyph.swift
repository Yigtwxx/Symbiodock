import Foundation

/// A tool's pet: the figure the tool is known by, built from seven vertical bars with
/// round ends, the way the island's level bars are. All measures are fractions of the
/// figure's side.
public struct AgentPetGlyph: Equatable, Sendable {
    /// A solid stretch of a bar. 0 is the top of the figure, 1 its bottom.
    public struct Segment: Equatable, Sendable {
        public let top: Double
        public let bottom: Double

        public init(top: Double, bottom: Double) {
            self.top = top
            self.bottom = bottom
        }
    }

    public static let columnCount = 7
    /// A bar is twice as wide as the gap beside it.
    public static let barWidth = 0.1
    /// From one bar's leading edge to the next.
    public static let pitch = 0.15

    /// The bars, left to right. A bar with several stretches has breaks: eyes, openings.
    public let columns: [[Segment]]

    private init(_ columns: [[(Double, Double)]]) {
        self.columns = columns.map { $0.map { Segment(top: $0.0, bottom: $0.1) } }
    }

    /// A figure that is the same on both sides of its middle bar.
    private static func mirrored(
        _ side: [[(Double, Double)]], middle: [(Double, Double)]
    ) -> AgentPetGlyph {
        AgentPetGlyph(side + [middle] + side.reversed())
    }

    public static func glyph(for tool: AgentTool) -> AgentPetGlyph {
        switch tool {
        case .claudeCode:
            // A blocky body with a flat top, two eyes, a stub arm on each side, and two legs
            // that carry on below the eyes.
            mirrored(
                [[(0.42, 0.62)], [(0.12, 0.70)], [(0.12, 0.30), (0.42, 0.88)]],
                middle: [(0.12, 0.70)])
        case .codex:
            // A cloud: a flat base with rounded ends under a small bump and a bigger one,
            // with two eyes under the bigger one.
            AgentPetGlyph([
                [(0.56, 0.76)], [(0.38, 0.82)], [(0.40, 0.82)], [(0.24, 0.50), (0.60, 0.82)],
                [(0.18, 0.82)], [(0.24, 0.50), (0.60, 0.82)], [(0.48, 0.76)],
            ])
        case .geminiCLI:
            // A four-pointed star: one tall bar, quickly shorter towards the sides.
            mirrored([[(0.45, 0.55)], [(0.38, 0.62)], [(0.26, 0.74)]], middle: [(0.05, 0.95)])
        case .cursorAgent:
            // A hexagon with upright sides whose middle bar is split, like the near corner
            // of a cube.
            mirrored(
                [[(0.27, 0.73)], [(0.20, 0.80)], [(0.13, 0.87)]],
                middle: [(0.06, 0.42), (0.58, 0.94)])
        case .openCode:
            // An empty frame with a tall cursor block inside, where a prompt would start.
            AgentPetGlyph([
                [(0.14, 0.86)], [(0.14, 0.26), (0.74, 0.86)],
                [(0.14, 0.26), (0.38, 0.62), (0.74, 0.86)], [(0.14, 0.26), (0.74, 0.86)],
                [(0.14, 0.26), (0.74, 0.86)], [(0.14, 0.26), (0.74, 0.86)], [(0.14, 0.86)],
            ])
        case .aider:
            // An "A": steps rising to a peak, with a crossbar.
            mirrored(
                [[(0.64, 0.94)], [(0.36, 0.94)], [(0.16, 0.64)]],
                middle: [(0.06, 0.26), (0.46, 0.64)])
        case .copilotCLI:
            // A domed head with two large goggle openings, each two bars wide, and an ear
            // on each side.
            mirrored(
                [[(0.32, 0.66)], [(0.16, 0.32), (0.52, 0.80)], [(0.10, 0.32), (0.52, 0.88)]],
                middle: [(0.08, 0.90)])
        }
    }
}

/// How a pet moves. Pure functions of time, so the views only draw.
public enum AgentPetMotion {
    /// How far the top of a bar rises or sinks while its session works.
    public static let swayAmplitude = 0.05
    /// How high the pet jumps while its session needs input.
    public static let hopHeight = 0.12
    /// The same beat as the status mark's knocks: two hops, then rest.
    public static let hopPeriod: TimeInterval = 2.4
    public static let hopLength: TimeInterval = 0.3

    /// The rise (positive) or fall of one bar's top at `time`: a wave passing through
    /// the figure from left to right.
    public static func sway(column: Int, at time: TimeInterval) -> Double {
        swayAmplitude * sin(time * 4.2 - Double(column) * 0.9)
    }

    /// How far above its place the pet is at `time`.
    public static func hop(at time: TimeInterval) -> Double {
        var beat = time.truncatingRemainder(dividingBy: hopPeriod)
        if beat < 0 { beat += hopPeriod }
        guard beat < 2 * hopLength else { return 0 }
        let local = beat.truncatingRemainder(dividingBy: hopLength) / hopLength
        return hopHeight * sin(.pi * local)
    }
}
