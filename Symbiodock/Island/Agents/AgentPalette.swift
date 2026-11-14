import SwiftUI
import SymbiodockCore

/// The colours the agents bring to the black island: two for what a session's state
/// says, and one for each tool's pet.
enum AgentPalette {
    /// A session waits for the user. #FF4D4F
    static let alert = Color(red: 1.0, green: 77.0 / 255.0, blue: 79.0 / 255.0)
    /// A session has finished. #63E6A9
    static let mint = Color(red: 99.0 / 255.0, green: 230.0 / 255.0, blue: 169.0 / 255.0)

    /// The colour a tool is known by, as red, green and blue from 0 to 1. None of them is
    /// the alert red or the finished mint. `position` runs from 0 at a pet's left edge to
    /// 1 at its right: Codex goes from blue to violet across its pet.
    private static func components(
        for tool: AgentTool, across position: Double
    ) -> (red: Double, green: Double, blue: Double) {
        switch tool {
        case .claudeCode: return (217.0 / 255.0, 119.0 / 255.0, 87.0 / 255.0)  // #D97757
        case .codex:
            let blue = (79.0 / 255.0, 156.0 / 255.0, 249.0 / 255.0)  // #4F9CF9
            let violet = (139.0 / 255.0, 92.0 / 255.0, 246.0 / 255.0)  // #8B5CF6
            let part = min(max(position, 0), 1)
            return (
                blue.0 + (violet.0 - blue.0) * part, blue.1 + (violet.1 - blue.1) * part,
                blue.2 + (violet.2 - blue.2) * part
            )
        case .geminiCLI: return (157.0 / 255.0, 123.0 / 255.0, 1.0)  // #9D7BFF
        case .cursorAgent: return (215.0 / 255.0, 215.0 / 255.0, 219.0 / 255.0)  // #D7D7DB
        case .openCode: return (240.0 / 255.0, 217.0 / 255.0, 168.0 / 255.0)  // #F0D9A8
        case .aider: return (163.0 / 255.0, 230.0 / 255.0, 53.0 / 255.0)  // #A3E635
        case .copilotCLI: return (242.0 / 255.0, 127.0 / 255.0, 192.0 / 255.0)  // #F27FC0
        }
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
