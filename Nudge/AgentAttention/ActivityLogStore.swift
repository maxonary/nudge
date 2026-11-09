import AppKit
import Foundation

/// The notch's short log of recent agent requests and nudges. It survives a
/// restart in a small JSON file; see ActivityLogFile for what is kept.
@MainActor
final class ActivityLogStore: ObservableObject {
    static let shared = ActivityLogStore()

    @Published private(set) var log: ActivityLog {
        didSet {
            guard log != oldValue else { return }
            do {
                try file.save(log)
            } catch {
                NSLog("Nudge: saving the activity log failed: \(error.localizedDescription)")
            }
        }
    }

    private let file: ActivityLogFile

    init(file: ActivityLogFile = ActivityLogFile(url: ActivityLogStore.defaultURL)) {
        self.file = file
        self.log = file.load()
    }

    nonisolated static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nudge", isDirectory: true)
            .appendingPathComponent("activity-log.json")
    }

    var entries: [ActivityLogEntry] { log.entries }

    // MARK: Agent events

    func recordCompletion(_ completion: AgentCompletion, envelope: AgentEventEnvelope, shown: Bool) {
        log.record(.completion(completion, envelope: envelope, date: Date(), shown: shown))
    }

    func recordQuestion(_ questionSet: AgentQuestionSet, envelope: AgentEventEnvelope, claimed: Bool) {
        log.record(.question(questionSet, envelope: envelope, date: Date(), claimed: claimed))
    }

    func recordApproval(_ approval: AgentApproval, envelope: AgentEventEnvelope, claimed: Bool) {
        log.record(.approval(approval, envelope: envelope, date: Date(), claimed: claimed))
    }

    func settle(id: String, outcome: String) {
        log.settle(id: id, outcome: outcome)
    }

    func markMissed(id: String) {
        log.markMissed(id: id)
    }

    // MARK: Nudges

    func recordNudge(_ ping: NudgePing) {
        let summary = ActivityLogEntry.plainSummary(ping.message)
        log.record(ActivityLogEntry(
            id: "nudge-\(ping.sender)-\(ping.receivedAt.timeIntervalSince1970)",
            kind: .nudge,
            title: ping.gif != nil && summary == nil ? "\(ping.sender) hat ein GIF geschickt" : "\(ping.sender) winkt dir",
            summary: summary,
            sender: ping.sender,
            date: ping.receivedAt,
            status: .unhandled
        ))
    }
}
