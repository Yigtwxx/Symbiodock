#if DEBUG
import Foundation
import SymbiodockCore

/// A fixed set of sessions for looking at the Agents tab without running an agent:
/// `open --env SYMBIODOCK_DEMO_AGENTS=1 build/Build/Products/Debug/Symbiodock.app`.
/// The value picks the set: `1` all states, `working`, `finished`, `quiet`.
@MainActor
enum DemoAgents {
    static var requested: String? {
        ProcessInfo.processInfo.environment["SYMBIODOCK_DEMO_AGENTS"]
    }

    static func apply(_ set: String, to state: IslandState, now: Date = Date()) {
        func session(
            _ id: String, _ tool: AgentTool, _ title: String, _ project: String,
            _ activity: AgentActivity, minutes: Double
        ) -> AgentSession {
            AgentSession(
                id: id, tool: tool, title: title, projectPath: "/Users/demo/\(project)",
                activity: activity, since: now.addingTimeInterval(-minutes * 60), pid: nil,
                hostAppPID: ProcessInfo.processInfo.processIdentifier)
        }
        let ask = session(
            "a", .claudeCode, "fix-login-flow", "storefront",
            .needsInput(prompt: "Which of the two migrations should run first?"), minutes: 1)
        let work = session("b", .codex, "Tune the monitor", "dotfiles", .working, minutes: 2)
        let done = session("c", .claudeCode, "api-refactor", "backend", .idle, minutes: 0.5)
        let open = session("d", .geminiCLI, "notes", "notes", .running, minutes: 40)
        let idle = session("e", .aider, "parser", "parser", .idle, minutes: 12)

        switch set {
        case "working":
            state.setAgentSessions([work, idle])
        case "finished":
            state.setAgentSessions([session("c", .claudeCode, "api-refactor", "backend", .working, minutes: 3)])
            state.setAgentSessions([done])
        case "quiet":
            state.setAgentSessions([open, idle])
        default:
            // `c` is seen working first, so that it shows as finished.
            state.setAgentSessions([
                ask, work, session("c", .claudeCode, "api-refactor", "backend", .working, minutes: 3),
                open, idle,
            ])
            state.setAgentSessions([ask, work, done, open, idle])
        }
    }
}
#endif
