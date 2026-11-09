import Foundation
import Testing
@testable import NudgeAgentCore

struct ActivityLogEntryTests {
    private let host = AgentHost(appName: "Conductor", bundleID: "com.conductor.app")

    private func envelope(_ event: AgentEvent, project: String? = nil, cwd: String = "/Users/s/code/nudge") -> AgentEventEnvelope {
        AgentEventEnvelope(protocolVersion: 1, source: .claudeCode, cwd: cwd, project: project, host: host, event: event)
    }

    @Test
    func completionSummarizesTheAgentsLastMessageAsPlainText() {
        let completion = AgentCompletion(
            id: "c1", source: .claudeCode, context: "/Users/s/code/nudge", title: "Claude Code finished",
            message: "## Fertig\n\n**Merge** von `main` ist durch.\n- Tests laufen"
        )
        let entry = ActivityLogEntry.completion(completion, envelope: envelope(.completion(completion)), date: Date(), shown: true)

        #expect(entry.title == "Claude Code ist fertig")
        #expect(entry.summary == "Fertig Merge von main ist durch. Tests laufen")
        #expect(entry.project == "nudge")
        #expect(entry.status == .unhandled)
    }

    @Test
    func longSummariesAreShortenedForTheLog() {
        let completion = AgentCompletion(
            id: "c2", source: .claudeCode, context: "x", title: "t",
            message: String(repeating: "Wort ", count: 200)
        )
        let entry = ActivityLogEntry.completion(completion, envelope: envelope(.completion(completion)), date: Date(), shown: true)

        let summary = entry.summary ?? ""
        #expect(summary.count <= ActivityLogEntry.summaryLimit)
        #expect(summary.hasSuffix("…"))
    }

    @Test
    func approvalKeepsItsDescriptionButNeverTheCommand() {
        let described = AgentApproval(
            id: "a1", source: .claudeCode, toolName: "Bash", detail: "Änderungen pushen",
            command: "git push --force", allowsClaudeSessionRule: false
        )
        let bare = AgentApproval(
            id: "a2", source: .claudeCode, toolName: "Bash", detail: "git push --force",
            command: "git push --force", allowsClaudeSessionRule: false
        )

        let first = ActivityLogEntry.approval(described, envelope: envelope(.approval(described), project: "rome"), date: Date(), claimed: true)
        let second = ActivityLogEntry.approval(bare, envelope: envelope(.approval(bare)), date: Date(), claimed: false)

        #expect(first.title == "Claude Code möchte Bash nutzen")
        #expect(first.summary == "Änderungen pushen")
        #expect(first.project == "rome")
        #expect(first.status == .pending)
        #expect(second.summary == nil)
        #expect(second.status == .handled("Im Agent"))
    }

    @Test
    func questionUsesTheFirstPromptAsSummary() {
        let set = AgentQuestionSet(id: "q1", header: "Höhe", questions: [
            AgentQuestion(id: "a", prompt: "Wie hoch soll die Notch werden?", choices: [], multiSelect: false, allowsFreeform: true),
        ])
        let entry = ActivityLogEntry.question(set, envelope: envelope(.question(set)), date: Date(), claimed: true)

        #expect(entry.title == "Claude Code fragt")
        #expect(entry.summary == "Wie hoch soll die Notch werden?")
    }
}
