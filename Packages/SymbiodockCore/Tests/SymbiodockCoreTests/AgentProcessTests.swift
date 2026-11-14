import Foundation
import Testing
@testable import SymbiodockCore

struct AgentProcessTests {
    private let start = Date(timeIntervalSince1970: 10_000)

    private func process(
        _ pid: Int32, parent: Int32 = 1, _ path: String, _ arguments: [String] = [],
        cwd: String? = nil, terminal: Int32? = 16_777_220, startOffset: TimeInterval = 0
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid, parentPID: parent, executablePath: path, arguments: arguments,
            workingDirectory: cwd, startTime: start.addingTimeInterval(startOffset),
            terminal: terminal)
    }

    @Test func nativeExecutablesAreMatchedByName() {
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/gemini")) == .geminiCLI)
        #expect(AgentProcessMatcher.tool(for: process(1, "/Users/me/.local/bin/cursor-agent")) == .cursorAgent)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/opencode")) == .openCode)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/aider")) == .aider)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/copilot")) == .copilotCLI)
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
                == .codex)
    }

    @Test func scriptsRunByAnInterpreterAreMatchedByTheirPath() {
        let node = "/opt/homebrew/bin/node"
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, node, ["node", "/opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js"]))
                == .geminiCLI)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node", "/opt/homebrew/bin/gemini"])) == .geminiCLI)
        // `-m` after the script is the tool's own option, not Python's module switch.
        #expect(
            AgentProcessMatcher.tool(for: process(1, node, ["node", "/opt/homebrew/bin/gemini", "-m", "some-model"]))
                == .geminiCLI)
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, node, ["node", "--no-warnings", "/usr/local/lib/node_modules/@github/copilot/index.js"]))
                == .copilotCLI)
        #expect(
            AgentProcessMatcher.tool(for: process(1, node, ["node", "/Users/me/.npm/opencode-ai/bin/opencode.js"]))
                == .openCode)
        #expect(
            AgentProcessMatcher.tool(for: process(1, node, ["node", "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"]))
                == .codex)
        #expect(
            AgentProcessMatcher.tool(
                for: process(1, node, ["node", "/Users/me/.local/share/cursor-agent/versions/2026.01.02/index.js"]))
                == .cursorAgent)
        #expect(
            AgentProcessMatcher.tool(for: process(1, "/usr/bin/python3", ["python3", "/Users/me/.local/bin/aider"]))
                == .aider)
        #expect(
            AgentProcessMatcher.tool(for: process(1, "/usr/bin/python3.12", ["python3.12", "-m", "aider", "--model", "x"]))
                == .aider)
    }

    @Test func nearMissesAreNotMatched() {
        let node = "/opt/homebrew/bin/node"
        #expect(AgentProcessMatcher.tool(for: process(1, "/usr/bin/vim", ["vim", "/Users/me/aider/notes.md"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node", "/Users/me/copilot/server.js"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node", "server.js", "/opt/homebrew/bin/gemini"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, node, ["node"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, "/usr/bin/python3", ["python3", "-m", "http.server"])) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, "/opt/homebrew/bin/gemini-helper")) == nil)
        #expect(AgentProcessMatcher.tool(for: process(1, "/bin/zsh", ["zsh", "-c", "gemini"])) == nil)
        #expect(
            AgentProcessMatcher.tool(for: process(1, "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex-code-mode-host"))
                == nil)
    }

    @Test func interpreters() {
        #expect(AgentProcessMatcher.isInterpreter("/opt/homebrew/bin/node"))
        #expect(AgentProcessMatcher.isInterpreter("/usr/bin/python3"))
        #expect(AgentProcessMatcher.isInterpreter("/opt/homebrew/Cellar/python@3.12/bin/Python"))
        #expect(AgentProcessMatcher.isInterpreter("/Users/me/.bun/bin/bun"))
        #expect(!AgentProcessMatcher.isInterpreter("/bin/zsh"))
        #expect(!AgentProcessMatcher.isInterpreter("/opt/homebrew/bin/gemini"))
    }

    @Test func oneRowPerToolAndTerminal() {
        let sessions = AgentProcessMatcher.sessions(
            for: .geminiCLI,
            in: [
                process(10, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Alpha", terminal: 1, startOffset: 5),
                process(11, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Alpha", terminal: 1, startOffset: 9),
                process(12, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Beta", terminal: 2),
                process(13, "/opt/homebrew/bin/gemini", cwd: "/Users/me/Projects/Gamma", terminal: nil),
                process(14, "/opt/homebrew/bin/aider", cwd: "/Users/me/Projects/Delta", terminal: 3),
            ])
        #expect(sessions.map(\.id) == ["geminiCLI:tty1", "geminiCLI:tty2"])
        #expect(sessions.map(\.title) == ["Alpha", "Beta"])
        #expect(sessions.map(\.pid) == [10, 12])
        #expect(sessions.allSatisfy { $0.activity == .running && $0.tool == .geminiCLI })
        #expect(sessions[0].since == start.addingTimeInterval(5))
        #expect(sessions[0].projectPath == "/Users/me/Projects/Alpha")
    }

    @Test func aProcessWithoutAFolderIsNamedAfterItsTool() {
        let sessions = AgentProcessMatcher.sessions(
            for: .aider, in: [process(1, "/opt/homebrew/bin/aider", cwd: nil, terminal: 4)])
        #expect(sessions.map(\.title) == ["Aider"])
    }

    @Test func ancestorsWalkUpToTheTop() {
        let processes = [
            process(100, parent: 50, "/opt/homebrew/bin/gemini"),
            process(50, parent: 20, "/bin/zsh"),
            process(20, parent: 1, "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
        ]
        #expect(ProcessTree.ancestors(of: 100, in: processes) == [50, 20])
        #expect(ProcessTree.ancestors(of: 20, in: processes) == [])
        #expect(ProcessTree.ancestors(of: 999, in: processes) == [])
    }

    @Test func ancestorsSurviveALoop() {
        let processes = [
            process(100, parent: 50, "/bin/a"),
            process(50, parent: 100, "/bin/b"),
        ]
        #expect(ProcessTree.ancestors(of: 100, in: processes) == [50])
    }

    @Test func theProcessLevelProviderListsItsOwnTool() async {
        let context = AgentScanContext(
            now: start,
            processes: [
                process(1, "/opt/homebrew/bin/opencode", cwd: "/Users/me/Projects/Alpha", terminal: 1),
                process(2, "/opt/homebrew/bin/aider", cwd: "/Users/me/Projects/Beta", terminal: 2),
            ])
        let provider = ProcessLevelProvider(tool: .openCode)
        #expect(provider.tool == .openCode)
        #expect(await provider.sessions(in: context).map(\.id) == ["openCode:tty1"])
    }
}
