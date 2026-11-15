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

    /// Folders whose changes should start a scan at once: Claude Code writes a session's
    /// file there the moment its status changes.
    static func wakeFolders() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".claude/sessions", isDirectory: true)]
    }
}
