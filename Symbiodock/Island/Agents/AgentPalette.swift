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
        case .claudeCode: [(245, 150, 95), (235, 112, 70), (205, 78, 48)]  // #F5965F #EB7046 #CD4E30
        case .codex: [(64, 150, 255), (140, 82, 255)]  // #4096FF #8C52FF
        case .geminiCLI: [(60, 135, 255), (150, 105, 255), (255, 120, 165)]  // #3C87FF #9669FF #FF78A5
        case .cursorAgent: [(250, 250, 252), (190, 190, 204)]  // #FAFAFC #BEBECC
        case .openCode: [(255, 232, 170), (240, 175, 75)]  // #FFE8AA #F0AF4B
        case .aider: [(210, 250, 70), (100, 220, 40)]  // #D2FA46 #64DC28
        case .copilotCLI: [(160, 120, 255), (255, 105, 190)]  // #A078FF #FF69BE
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
