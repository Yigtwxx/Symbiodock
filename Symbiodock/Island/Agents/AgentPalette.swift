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
    /// the alert red or the finished mint.
    private static func components(for tool: AgentTool) -> (red: Double, green: Double, blue: Double) {
        switch tool {
        case .claudeCode: (217.0 / 255.0, 119.0 / 255.0, 87.0 / 255.0)  // #D97757
        case .codex: (79.0 / 255.0, 156.0 / 255.0, 249.0 / 255.0)  // #4F9CF9
        case .geminiCLI: (157.0 / 255.0, 123.0 / 255.0, 1.0)  // #9D7BFF
        case .cursorAgent: (215.0 / 255.0, 215.0 / 255.0, 219.0 / 255.0)  // #D7D7DB
        case .openCode: (240.0 / 255.0, 217.0 / 255.0, 168.0 / 255.0)  // #F0D9A8
        case .aider: (163.0 / 255.0, 230.0 / 255.0, 53.0 / 255.0)  // #A3E635
        case .copilotCLI: (242.0 / 255.0, 127.0 / 255.0, 192.0 / 255.0)  // #F27FC0
        }
    }

    /// A tool's colour at the given strength, 1 being the colour itself. Weaker is the
    /// colour mixed towards the island's black: an opaque colour, so that lines drawn over
    /// each other do not add up.
    static func tint(for tool: AgentTool, strength: Double = 1) -> Color {
        let color = components(for: tool)
        let amount = min(max(strength, 0), 1)
        return Color(red: color.red * amount, green: color.green * amount, blue: color.blue * amount)
    }
}
