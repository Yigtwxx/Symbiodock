import Foundation

/// One running process, as much of it as session detection needs.
public struct ProcessSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32
    public let executablePath: String
    /// `argv`, read only for interpreter processes; empty otherwise.
    public var arguments: [String]
    /// Read only for processes that belong to a known tool.
    public var workingDirectory: String?
    public let startTime: Date
    /// The controlling terminal's device number; nil for a process without one.
    public let terminal: Int32?

    public init(
        pid: Int32, parentPID: Int32, executablePath: String, arguments: [String] = [],
        workingDirectory: String? = nil, startTime: Date, terminal: Int32?
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.startTime = startTime
        self.terminal = terminal
    }
}

/// Tells which AI coding tool a process belongs to, from its executable and arguments.
public enum AgentProcessMatcher {
    /// Executable or script names, without extension.
    private static let names: [String: AgentTool] = [
        "gemini": .geminiCLI,
        "cursor-agent": .cursorAgent,
        "opencode": .openCode,
        "aider": .aider,
        "copilot": .copilotCLI,
        "codex": .codex,
    ]
    /// Package folders that identify a tool wherever its entry script is called.
    private static let packages: [(marker: String, tool: AgentTool)] = [
        ("@google/gemini-cli", .geminiCLI),
        ("@github/copilot", .copilotCLI),
        ("@openai/codex", .codex),
        ("opencode-ai", .openCode),
        // Cursor's agent runs as `node …/cursor-agent/versions/<version>/index.js`.
        ("/cursor-agent/", .cursorAgent),
    ]
    private static let scriptExtensions: Set<String> = ["js", "mjs", "cjs", "py"]

    /// Whether the executable runs a script, so that the tool is named in its arguments.
    public static func isInterpreter(_ executablePath: String) -> Bool {
        let name = (executablePath as NSString).lastPathComponent.lowercased()
        return name == "node" || name == "bun" || name == "deno" || name.hasPrefix("python")
    }

    public static func tool(for process: ProcessSnapshot) -> AgentTool? {
        let name = (process.executablePath as NSString).lastPathComponent.lowercased()
        if let tool = names[name] { return tool }
        guard isInterpreter(process.executablePath) else { return nil }

        let arguments = Array(process.arguments.dropFirst())
        // The script is the first argument that is not an option. Python can name a module
        // instead (`python -m aider`); for other interpreters `-m` is the script's own flag.
        var script: String?
        for (index, argument) in arguments.enumerated() {
            if argument == "-m", name.hasPrefix("python") {
                guard arguments.indices.contains(index + 1) else { return nil }
                return names[arguments[index + 1].lowercased()] == .aider ? .aider : nil
            }
            if !argument.hasPrefix("-") {
                script = argument
                break
            }
        }
        guard let script else { return nil }
        if let package = packages.first(where: { script.contains($0.marker) }) { return package.tool }
        let file = (script as NSString).lastPathComponent
        let stem = scriptExtensions.contains((file as NSString).pathExtension.lowercased())
            ? (file as NSString).deletingPathExtension : file
        return names[stem.lowercased()]
    }

    /// Process-level sessions of one tool: one per terminal, from its oldest process.
    /// Processes without a terminal (helpers, editor extensions) are not sessions.
    public static func sessions(
        for tool: AgentTool, in processes: [ProcessSnapshot]
    ) -> [AgentSession] {
        var oldest: [Int32: ProcessSnapshot] = [:]
        for process in processes {
            guard let terminal = process.terminal, self.tool(for: process) == tool else { continue }
            if let known = oldest[terminal], known.startTime <= process.startTime { continue }
            oldest[terminal] = process
        }
        return oldest.keys.sorted().compactMap { terminal in
            guard let process = oldest[terminal] else { return nil }
            let folder = process.workingDirectory.map { ($0 as NSString).lastPathComponent }
            let title = folder.flatMap { $0.isEmpty || $0 == "/" ? nil : $0 }
            return AgentSession(
                id: "\(tool.rawValue):tty\(terminal)",
                tool: tool,
                title: title ?? tool.displayName,
                projectPath: process.workingDirectory,
                activity: .running,
                since: process.startTime,
                pid: process.pid)
        }
    }
}

public enum ProcessTree {
    /// The parent, grandparent and so on of a process, nearest first, stopping before
    /// `launchd`, at a process that is not in the list, or at a loop.
    public static func ancestors(of pid: Int32, in processes: [ProcessSnapshot]) -> [Int32] {
        let parents = Dictionary(
            processes.map { ($0.pid, $0.parentPID) }, uniquingKeysWith: { first, _ in first })
        var chain: [Int32] = []
        var visited: Set<Int32> = [pid]
        var current = pid
        while let parent = parents[current], parent > 1, parents[parent] != nil,
              visited.insert(parent).inserted {
            chain.append(parent)
            current = parent
        }
        return chain
    }
}

/// What every provider gets for one scan.
public struct AgentScanContext: Sendable {
    public let now: Date
    public let processes: [ProcessSnapshot]

    public init(now: Date, processes: [ProcessSnapshot]) {
        self.now = now
        self.processes = processes
    }
}

/// Finds the sessions of one tool. A provider returns what it is sure of: a record it
/// cannot read is left out, and it never throws.
public protocol AgentSessionProvider: Sendable {
    var tool: AgentTool { get }
    func sessions(in context: AgentScanContext) async -> [AgentSession]
}

/// Detection without any knowledge of the tool's files: a row says the tool is open.
public struct ProcessLevelProvider: AgentSessionProvider {
    public let tool: AgentTool

    public init(tool: AgentTool) {
        self.tool = tool
    }

    public func sessions(in context: AgentScanContext) async -> [AgentSession] {
        AgentProcessMatcher.sessions(for: tool, in: context.processes)
    }
}
