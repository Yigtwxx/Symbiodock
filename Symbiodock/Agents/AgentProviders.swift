import Foundation
import SymbiodockCore

/// Every tool whose sessions the island shows.
enum AgentProviders {
    static func all() -> [any AgentSessionProvider] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ClaudeCodeProvider(home: home.appendingPathComponent(".claude", isDirectory: true)),
        ]
    }
}
