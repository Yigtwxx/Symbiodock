import SwiftUI
import SymbiodockCore

/// The colours the agents bring to the black island: two for what a session's state
/// says, and one for each tool's pet.
enum AgentPalette {
    /// A session waits for the user. #FF4D4F
    static let alert = Color(red: 1.0, green: 77.0 / 255.0, blue: 79.0 / 255.0)
    /// A session has finished. #63E6A9
    static let mint = Color(red: 99.0 / 255.0, green: 230.0 / 255.0, blue: 169.0 / 255.0)

    /// The colour a tool is known by. None of them is the alert red or the finished mint.
    static func tint(for tool: AgentTool) -> Color {
        switch tool {
        case .claudeCode: Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)  // #D97757
        case .codex: Color(red: 79.0 / 255.0, green: 156.0 / 255.0, blue: 249.0 / 255.0)  // #4F9CF9
        case .geminiCLI: Color(red: 157.0 / 255.0, green: 123.0 / 255.0, blue: 1.0)  // #9D7BFF
        case .cursorAgent: Color(red: 215.0 / 255.0, green: 215.0 / 255.0, blue: 219.0 / 255.0)  // #D7D7DB
        case .openCode: Color(red: 240.0 / 255.0, green: 217.0 / 255.0, blue: 168.0 / 255.0)  // #F0D9A8
        case .aider: Color(red: 163.0 / 255.0, green: 230.0 / 255.0, blue: 53.0 / 255.0)  // #A3E635
        case .copilotCLI: Color(red: 242.0 / 255.0, green: 127.0 / 255.0, blue: 192.0 / 255.0)  // #F27FC0
        }
    }
}
