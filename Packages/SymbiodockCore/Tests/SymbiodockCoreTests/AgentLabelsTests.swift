import Foundation
import Testing
@testable import SymbiodockCore

struct AgentLabelsTests {
    @Test func durations() {
        #expect(AgentLabels.duration(-5) == "<1m")
        #expect(AgentLabels.duration(59) == "<1m")
        #expect(AgentLabels.duration(60) == "1m")
        #expect(AgentLabels.duration(59 * 60 + 59) == "59m")
        #expect(AgentLabels.duration(3600) == "1h 0m")
        #expect(AgentLabels.duration(3600 + 4 * 60) == "1h 4m")
        #expect(AgentLabels.duration(.infinity) == "<1m")
        #expect(AgentLabels.duration(1e300) == "87600h 0m")
    }

    @Test func statusLabels() {
        let since = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 125)
        #expect(AgentLabels.status(.working, since: since, now: now) == "Working 2m")
        #expect(AgentLabels.status(.needsInput(prompt: "x"), since: since, now: now) == "Needs input")
        #expect(AgentLabels.status(.finished, since: since, now: now) == "Done 2m")
        #expect(AgentLabels.status(.running, since: since, now: now) == "Running")
        #expect(AgentLabels.status(.idle, since: since, now: now) == "Idle 2m")
    }

    @Test func summaryLeavesOutEmptyGroups() {
        #expect(AgentLabels.summary(needsInput: 0, working: 0) == nil)
        #expect(AgentLabels.summary(needsInput: 1, working: 0) == "1 needs input")
        #expect(AgentLabels.summary(needsInput: 0, working: 2) == "2 working")
        #expect(AgentLabels.summary(needsInput: 1, working: 2) == "1 needs input · 2 working")
    }

    @Test func toolNames() {
        #expect(AgentTool.claudeCode.displayName == "Claude Code")
        #expect(AgentTool.copilotCLI.displayName == "Copilot CLI")
        #expect(AgentTool.allCases.count == 7)
    }
}
