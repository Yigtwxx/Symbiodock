import SwiftUI
import SymbiodockCore

/// The colours the agents bring to the black island: two for what a session's state
/// says, and a run of colours for each tool's pet.
enum AgentPalette {
    /// The four colours of a tool's working light, in the order they follow each other
    /// along the island's edge: the pet's own tones and their neighbours. None is the alert
    /// amber, the finished mint or the compacting purple. The working arc runs from the
    /// first to the second; a sub-agent's satellite has one of the four.
    static func aurora(for tool: AgentTool) -> [Color] {
        let hex: [UInt32] =
            switch tool {
            case .claudeCode: [0xFFB347, 0xFF4D6D, 0xFF7A3D, 0xFFD166]
            case .codex: [0x39C8FF, 0xA259FF, 0x5B7CFF, 0xE05CFF]
            case .geminiCLI: [0x3C87FF, 0xFF78A5, 0x9669FF, 0x5CD0FF]
            case .cursorAgent: [0xFAFAFC, 0xB9C6FF, 0xBEBECC, 0xE6D9FF]
            case .openCode: [0xFFE8AA, 0xFF9F5A, 0xF0AF4B, 0xFFD98A]
            case .aider: [0xD2FA46, 0x39D353, 0x64DC28, 0xF2FF7A]
            case .copilotCLI: [0xA078FF, 0xFF69BE, 0xC86BFF, 0xFF9AD5]
            }
        return hex.map(color(hex:))
    }

    /// The mint tones the working light turns to while its session's finish seal plays, in
    /// the order they follow each other along the edge.
    static let auroraFinish: [Color] = [0x63E6A9, 0x9AEFC8, 0x63E6A9, 0xC9FFE6].map(color(hex:))

    private static func color(hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// A session waits for the user. #FFD60A, amber: red read as a failure.
    static let alert = Color(red: 1.0, green: 214.0 / 255.0, blue: 10.0 / 255.0)
    /// A session has finished. #63E6A9
    static let mint = Color(red: 99.0 / 255.0, green: 230.0 / 255.0, blue: 169.0 / 255.0)

    /// A session compacts its conversation. #BF5AF2, purple: apart from the tool colours,
    /// the mint and the amber.
    static let compacting = Color(red: 191.0 / 255.0, green: 90.0 / 255.0, blue: 242.0 / 255.0)

    /// The colours a tool's pet runs through, from its upper left to its lower right, as
    /// red, green and blue from 0 to 255. None of them is the alert amber or the finished mint;
    /// OpenCode's yellow never meets the amber, as OpenCode never needs input.
    private static func run(for tool: AgentTool) -> [(Double, Double, Double)] {
        switch tool {
        case .claudeCode: [(255, 170, 100), (255, 122, 61), (240, 78, 40)]  // #FFAA64 #FF7A3D #F04E28
        case .codex: [(60, 175, 255), (105, 115, 255), (165, 80, 255)]  // #3CAFFF #6973FF #A550FF
        case .geminiCLI: [(60, 135, 255), (150, 105, 255), (255, 120, 165)]  // #3C87FF #9669FF #FF78A5
        case .cursorAgent: [(250, 250, 252), (190, 190, 204)]  // #FAFAFC #BEBECC
        case .openCode: [(255, 232, 170), (255, 186, 80)]  // #FFE8AA #FFBA50
        case .aider: [(214, 255, 71), (116, 255, 46)]  // #D6FF47 #74FF2E
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
