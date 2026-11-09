import AppKit
import Foundation

/// The notch's short log of recent agent requests and nudges. In memory only:
/// it resets when Nudge quits, and nothing is written to disk.
@MainActor
final class ActivityLogStore: ObservableObject {
    static let shared = ActivityLogStore()

    @Published private(set) var log = ActivityLog()

    var entries: [ActivityLogEntry] { log.entries }

    // MARK: Agent events

    func recordCompletion(_ completion: AgentCompletion, envelope: AgentEventEnvelope, shown: Bool) {
        log.record(ActivityLogEntry(
            id: completion.id,
            kind: .completion,
            title: "\(Self.sourceName(envelope.source)) ist fertig",
            detail: Self.condensed(completion.message),
            source: envelope.source,
            host: envelope.host,
            date: Date(),
            status: shown ? .unhandled : .handled("Gesehen")
        ))
    }

    func recordQuestion(_ questionSet: AgentQuestionSet, envelope: AgentEventEnvelope, claimed: Bool) {
        log.record(ActivityLogEntry(
            id: questionSet.id,
            kind: .question,
            title: questionSet.questions.first?.prompt ?? "\(Self.sourceName(envelope.source)) hat eine Frage",
            source: envelope.source,
            host: envelope.host,
            date: Date(),
            status: claimed ? .pending : .handled("Im Agent")
        ))
    }

    func recordApproval(_ approval: AgentApproval, envelope: AgentEventEnvelope, claimed: Bool) {
        log.record(ActivityLogEntry(
            id: approval.id,
            kind: .approval,
            title: "\(Self.sourceName(envelope.source)) möchte \(approval.toolName) nutzen",
            detail: approval.command ?? approval.detail,
            source: envelope.source,
            host: envelope.host,
            date: Date(),
            status: claimed ? .pending : .handled("Im Agent")
        ))
    }

    func settle(id: String, outcome: String) {
        log.settle(id: id, outcome: outcome)
    }

    func markMissed(id: String) {
        log.markMissed(id: id)
    }

    // MARK: Nudges

    func recordNudge(_ ping: NudgePing) {
        let title: String
        if let message = Self.condensed(ping.message) {
            title = "\(ping.sender): \(message)"
        } else if ping.gif != nil {
            title = "\(ping.sender) hat ein GIF geschickt"
        } else {
            title = "\(ping.sender) winkt dir"
        }
        log.record(ActivityLogEntry(
            id: "nudge-\(ping.sender)-\(ping.receivedAt.timeIntervalSince1970)",
            kind: .nudge,
            title: title,
            sender: ping.sender,
            date: ping.receivedAt,
            status: .unhandled
        ))
    }

    // MARK: Helpers

    private static func sourceName(_ source: AgentSource) -> String {
        switch source {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    private static func condensed(_ text: String?) -> String? {
        guard let text else { return nil }
        let flattened = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flattened.isEmpty ? nil : flattened
    }
}
