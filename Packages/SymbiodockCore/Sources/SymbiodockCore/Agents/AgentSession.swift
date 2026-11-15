import Foundation

/// The AI coding tools whose sessions the island can show.
public enum AgentTool: String, CaseIterable, Sendable {
    case claudeCode, codex, geminiCLI, cursorAgent, openCode, aider, copilotCLI

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .cursorAgent: "Cursor Agent"
        case .openCode: "OpenCode"
        case .aider: "Aider"
        case .copilotCLI: "Copilot CLI"
        }
    }
}

/// What a session is doing, as far as its tool lets us read it.
public enum AgentActivity: Equatable, Sendable {
    case working
    /// Waiting for the user. `prompt` is the question, when it could be read.
    case needsInput(prompt: String?)
    /// The turn is over and the session waits for the next request.
    case idle
    /// The tool is running; nothing more is known.
    case running
}

/// One session of an AI coding tool on this Mac.
public struct AgentSession: Identifiable, Equatable, Sendable {
    /// "<tool>:<native id>", unique across tools.
    public let id: String
    public let tool: AgentTool
    /// The session's name, or its project folder's name.
    public let title: String
    public let projectPath: String?
    public let activity: AgentActivity
    /// When `activity` began.
    public let since: Date
    /// The tool's own process, when known.
    public let pid: Int32?
    /// The regular app that hosts the session (a terminal, an editor), when one was found.
    public var hostAppPID: Int32?
    /// Its subagents that are still worth showing; empty for a tool that has none.
    public var subagents: [AgentSubagent]

    public init(
        id: String, tool: AgentTool, title: String, projectPath: String?,
        activity: AgentActivity, since: Date, pid: Int32?, hostAppPID: Int32? = nil,
        subagents: [AgentSubagent] = []
    ) {
        self.id = id
        self.tool = tool
        self.title = title
        self.projectPath = projectPath
        self.activity = activity
        self.since = since
        self.pid = pid
        self.hostAppPID = hostAppPID
        self.subagents = subagents
    }

    /// The project folder's name, for display.
    public var projectName: String? {
        guard let projectPath else { return nil }
        let name = (projectPath as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
