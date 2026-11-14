import Foundation

/// A tool's pet: the figure the tool is known by, made of fine vertical lines with round
/// ends. Each figure is drawn on a square grid; every column of the grid becomes one line,
/// broken wherever the drawing has a hole (an eye, a prompt, an opening). Parts of a figure
/// stand at different depths, which the views draw as different strengths of the tool's
/// colour. All measures are fractions of the figure's side.
public struct AgentPetGlyph: Equatable, Sendable {
    /// A solid stretch of a line. 0 is the top of the figure, 1 its bottom.
    public struct Segment: Equatable, Sendable {
        public let top: Double
        public let bottom: Double
        /// 0 is in front, `depthCount - 1` is farthest back.
        public let depth: Int

        public init(top: Double, bottom: Double, depth: Int = 0) {
            self.top = top
            self.bottom = bottom
            self.depth = depth
        }
    }

    /// Figures are drawn on a grid of this many cells each way.
    public static let gridSize = 17
    public static let columnCount = gridSize
    /// A line is as wide as the gap beside it: 17 lines and 16 gaps fill the width.
    public static let barWidth = 1.0 / Double(2 * gridSize - 1)
    /// From one line's leading edge to the next.
    public static let pitch = 2 * barWidth
    /// In front, in the middle, at the back.
    public static let depthCount = 3

    /// The lines, left to right. A line with several stretches has breaks, or changes depth.
    public let columns: [[Segment]]

    /// What a character of a drawing stands for: `#` in front, `+` in the middle, `-` at
    /// the back; anything else is empty.
    private static func depth(of character: Character) -> Int? {
        switch character {
        case "#": 0
        case "+": 1
        case "-": 2
        default: nil
        }
    }

    /// Reads a drawing, top row first. A column of the drawing becomes a line; each run of
    /// ink at one depth becomes a stretch. Cells outside the drawing count as empty, so a
    /// short row cannot fail.
    init(art: [String]) {
        let rows = art.prefix(Self.gridSize).map(Array.init)
        let size = Double(Self.gridSize)
        columns = (0..<Self.gridSize).map { x in
            var segments: [Segment] = []
            var start = 0
            var current: Int?
            for y in 0...Self.gridSize {
                let here = y < rows.count && x < rows[y].count ? Self.depth(of: rows[y][x]) : nil
                guard here != current else { continue }
                if let current {
                    segments.append(
                        Segment(top: Double(start) / size, bottom: Double(y) / size, depth: current))
                }
                start = y
                current = here
            }
            return segments
        }
    }

    public static func glyph(for tool: AgentTool) -> AgentPetGlyph {
        AgentPetGlyph(art: art(for: tool))
    }

    /// The drawings. Each is `gridSize` rows of `gridSize` characters.
    static func art(for tool: AgentTool) -> [String] {
        switch tool {
        case .claudeCode:
            // A blocky creature: flat top, two eyes, an arm on each side, four legs, the far
            // pair behind.
            [
                ".................",
                ".................",
                ".................",
                "..#############..",
                "..#############..",
                "..###..###..###..",
                "++###..###..###++",
                "++###..###..###++",
                "++#############++",
                "..#############..",
                "..#############..",
                "...##.--.--.##...",
                "...##.--.--.##...",
                "...##.--.--.##...",
                ".................",
                ".................",
                ".................",
            ]
        case .codex:
            // A cloud with a prompt in it, ">" and "_", and a second cloud behind it.
            [
                ".................",
                ".................",
                "...........---...",
                ".........-------.",
                ".....###.--------",
                "...#######-------",
                "..#########------",
                ".###########-----",
                "#############----",
                "###.#########---.",
                "####.########....",
                "###.###...###....",
                "#############....",
                ".###########.....",
                ".................",
                ".................",
                ".................",
            ]
        case .geminiCLI:
            // A four-pointed star, and a small one far behind it.
            [
                ".................",
                ".............-...",
                ".......#.....-...",
                ".......#...-----.",
                ".......#.....-...",
                "......###....-...",
                "......###........",
                ".....#####.......",
                "...#########.....",
                "###############..",
                "...#########.....",
                ".....#####.......",
                "......###........",
                "......###........",
                ".......#.........",
                ".......#.........",
                ".......#.........",
            ]
        case .cursorAgent:
            // A cube seen from a corner: its top in front, one side in the middle, the other
            // at the back.
            [
                ".................",
                ".......###.......",
                ".....#######.....",
                "...###########...",
                ".+#############-.",
                ".+++#########---.",
                ".+++++#####-----.",
                ".+++++++#-------.",
                ".+++++++.-------.",
                ".+++++++.-------.",
                ".+++++++.-------.",
                "..++++++.------..",
                "....++++.----....",
                "......++.--......",
                ".................",
                ".................",
                ".................",
            ]
        case .openCode:
            // A terminal window with a prompt, ">" and "_", and a second window behind it.
            [
                ".................",
                "....-------------",
                "....-------------",
                "....--.........--",
                "#############..--",
                "#############..--",
                "##.........##..--",
                "##.+.......##..--",
                "##..+......##..--",
                "##...+.....##..--",
                "##..+......##----",
                "##.+..+++..##----",
                "##.........##....",
                "#############....",
                "#############....",
                ".................",
                ".................",
            ]
        case .aider:
            // The letter A, folded: its left stroke in front, the crossbar in the middle, the
            // right stroke turning away.
            [
                ".................",
                "........#........",
                ".......##+.......",
                ".......##+.......",
                "......##.++......",
                "......##.++......",
                ".....##...++.....",
                ".....##...++.....",
                "....##.....++....",
                "....##+++++++....",
                "...###+++++++-...",
                "...##.......--...",
                "..##.........--..",
                "..##.........--..",
                ".##...........--.",
                ".................",
                ".................",
            ]
        case .copilotCLI:
            // A helmeted head: two goggles with dark glass, two eyes below them, an ear on
            // each side.
            [
                ".................",
                ".....#######.....",
                "...###########...",
                "..#############..",
                ".###############.",
                ".##----###----##.",
                "+##----###----##+",
                "+##----###----##+",
                "+##----###----##+",
                "+###############+",
                ".###############.",
                ".#####.###.#####.",
                ".#####.###.#####.",
                "..#############..",
                "....#########....",
                ".................",
                ".................",
            ]
        }
    }
}

/// How a pet moves. Pure functions of time, so the views only draw.
public enum AgentPetMotion {
    /// How far the top of a line rises or sinks while its session works: under half a
    /// grid cell, less than a point on screen. Enough to see that it is alive, no more.
    public static let swayAmplitude = 0.025
    /// How high the pet jumps while its session needs input.
    public static let hopHeight = 0.08
    /// The same beat as the status mark's knocks: two hops, then rest.
    public static let hopPeriod: TimeInterval = 2.4
    public static let hopLength: TimeInterval = 0.3

    /// The rise (positive) or fall of one line's top at `time`. Every line breathes at its
    /// own slow pace (a cycle takes two to four seconds), so the figure stirs gently
    /// instead of marching in step.
    public static func sway(column: Int, at time: TimeInterval) -> Double {
        let pace = 2.4 + 0.9 * sin(Double(column) * 2.3)
        return swayAmplitude * sin(time * pace + Double(column) * 1.7)
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
