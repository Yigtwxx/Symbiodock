import Foundation
import SymbiodockCore

/// Every tool whose sessions the island shows.
enum AgentProviders {
    static func all() -> [any AgentSessionProvider] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let processLevel: [AgentTool] = [.geminiCLI, .cursorAgent, .openCode, .aider, .copilotCLI]
        return [
            ClaudeCodeProvider(home: home.appendingPathComponent(".claude", isDirectory: true)),
            CodexProvider(home: home.appendingPathComponent(".codex", isDirectory: true)),
        ] + processLevel.map { ProcessLevelProvider(tool: $0) }
    }
}
