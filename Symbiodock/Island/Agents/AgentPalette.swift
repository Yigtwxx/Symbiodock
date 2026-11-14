import SwiftUI
import SymbiodockCore

/// The colours the agents bring to the black island: two for what a session's state
/// says, and a run of colours for each tool's pet.
enum AgentPalette {
    /// A session waits for the user. #FF4D4F
    static let alert = Color(red: 1.0, green: 77.0 / 255.0, blue: 79.0 / 255.0)
    /// A session has finished. #63E6A9
    static let mint = Color(red: 99.0 / 255.0, green: 230.0 / 255.0, blue: 169.0 / 255.0)

    /// The colours a tool's pet runs through, from its upper left to its lower right, as
    /// red, green and blue from 0 to 255. None of them is the alert red or the finished mint.
    private static func run(for tool: AgentTool) -> [(Double, Double, Double)] {
        switch tool {
        case .claudeCode: [(233, 154, 110), (217, 119, 87), (185, 85, 58)]  // #E99A6E #D97757 #B9553A
        case .codex: [(79, 156, 249), (139, 92, 246)]  // #4F9CF9 #8B5CF6
        case .geminiCLI: [(78, 140, 255), (157, 123, 255), (240, 138, 168)]  // #4E8CFF #9D7BFF #F08AA8
        case .cursorAgent: [(244, 244, 247), (180, 180, 192)]  // #F4F4F7 #B4B4C0
        case .openCode: [(248, 233, 192), (221, 175, 99)]  // #F8E9C0 #DDAF63
        case .aider: [(214, 244, 92), (120, 210, 58)]  // #D6F45C #78D23A
        case .copilotCLI: [(167, 139, 250), (242, 127, 192)]  // #A78BFA #F27FC0
        }
    }

    /// A tool's colour at `position` along its run: 0 at the pet's upper left, 1 at its
    /// lower right.
    private static func components(
        for tool: AgentTool, across position: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let colors = run(for: tool)
        let place = (position.isFinite ? min(max(position, 0), 1) : 0.5) * Double(colors.count - 1)
        let lower = min(Int(place), colors.count - 2)
        let part = place - Double(lower)
        let from = colors[lower]
        let to = colors[lower + 1]
        return (
            (from.0 + (to.0 - from.0) * part) / 255, (from.1 + (to.1 - from.1) * part) / 255,
            (from.2 + (to.2 - from.2) * part) / 255
        )
    }

    /// A tool's colour at the given strength. 1 is the colour itself. Below 1 it is mixed
    /// towards the island's black, above 1 towards white (a part that glows), up to 2.
    /// The result is opaque, so that lines drawn over each other do not add up.
    static func tint(for tool: AgentTool, strength: Double = 1, across position: Double = 0.5) -> Color {
        let color = components(for: tool, across: position)
        let amount = min(max(strength, 0), 2)
        guard amount > 1 else {
            return Color(red: color.red * amount, green: color.green * amount, blue: color.blue * amount)
        }
        let white = amount - 1
        return Color(
            red: color.red + (1 - color.red) * white, green: color.green + (1 - color.green) * white,
            blue: color.blue + (1 - color.blue) * white)
    }
}
