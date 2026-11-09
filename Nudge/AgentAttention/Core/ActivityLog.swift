import Foundation

/// One recent notification shown in the notch's short log.
public struct ActivityLogEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: Codable, Equatable, Sendable {
        case completion
        case question
        case approval
        case nudge
    }

    public enum Status: Codable, Equatable, Sendable {
        /// A live agent request that can still be answered in Nudge.
        case pending
        /// Shown, but nobody acted on it yet.
        case unhandled
        /// Dealt with; the outcome says how ("Erlaubt", "Im Agent", "Gesehen").
        case handled(String)
    }

    public let id: String
    public let kind: Kind
    /// Short label: "Claude Code ist fertig", "Max winkt dir".
    public var title: String
    /// The useful part: what the agent wrote, the question, the request.
    public var summary: String?
    public var project: String?
    public var source: AgentSource?
    public var host: AgentHost?
    public var sender: String?
    public let date: Date
    public var status: Status

    public init(
        id: String,
        kind: Kind,
        title: String,
        summary: String? = nil,
        project: String? = nil,
        source: AgentSource? = nil,
        host: AgentHost? = nil,
        sender: String? = nil,
        date: Date,
        status: Status
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.project = project
        self.source = source
        self.host = host
        self.sender = sender
        self.date = date
        self.status = status
    }

    /// Handled entries recede so the eye lands on what still needs attention.
    public var isDimmed: Bool {
        if case .handled = status { return true }
        return false
    }
}

// MARK: - Building entries from agent events

extension ActivityLogEntry {
    public static let summaryLimit = 240

    public static func completion(
        _ completion: AgentCompletion,
        envelope: AgentEventEnvelope,
        date: Date,
        shown: Bool
    ) -> ActivityLogEntry {
        ActivityLogEntry(
            id: completion.id,
            kind: .completion,
            title: "\(sourceName(envelope.source)) ist fertig",
            summary: plainSummary(completion.message),
            project: projectName(envelope),
            source: envelope.source,
            host: envelope.host,
            date: date,
            status: shown ? .unhandled : .handled("Gesehen")
        )
    }

    public static func question(
        _ questionSet: AgentQuestionSet,
        envelope: AgentEventEnvelope,
        date: Date,
        claimed: Bool
    ) -> ActivityLogEntry {
        ActivityLogEntry(
            id: questionSet.id,
            kind: .question,
            title: "\(sourceName(envelope.source)) fragt",
            summary: plainSummary(questionSet.questions.first?.prompt),
            project: projectName(envelope),
            source: envelope.source,
            host: envelope.host,
            date: date,
            status: claimed ? .pending : .handled("Im Agent")
        )
    }

    /// Keeps the human description of the request, never the command itself.
    public static func approval(
        _ approval: AgentApproval,
        envelope: AgentEventEnvelope,
        date: Date,
        claimed: Bool
    ) -> ActivityLogEntry {
        let detail = approval.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDescription = !detail.isEmpty
            && detail != approval.command?.trimmingCharacters(in: .whitespacesAndNewlines)
            && detail != approval.toolName
        return ActivityLogEntry(
            id: approval.id,
            kind: .approval,
            title: "\(sourceName(envelope.source)) möchte \(approval.toolName) nutzen",
            summary: isDescription ? plainSummary(detail) : nil,
            project: projectName(envelope),
            source: envelope.source,
            host: envelope.host,
            date: date,
            status: claimed ? .pending : .handled("Im Agent")
        )
    }

    /// Agent text is often markdown over several lines; the log wants one
    /// plain, bounded line of it.
    public static func plainSummary(_ text: String?) -> String? {
        guard let text else { return nil }
        let markers: Set<String> = ["#", "##", "###", "####", "-", "*", ">", "•"]
        let words = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !markers.contains($0) }
            .map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "") }
            .filter { !$0.isEmpty }
        let flattened = words.joined(separator: " ")
        guard !flattened.isEmpty else { return nil }
        guard flattened.count > summaryLimit else { return flattened }
        let cut = flattened.prefix(summaryLimit - 1).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    private static func sourceName(_ source: AgentSource) -> String {
        switch source {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    private static func projectName(_ envelope: AgentEventEnvelope) -> String? {
        if let project = envelope.project?.trimmingCharacters(in: .whitespacesAndNewlines), !project.isEmpty {
            return project
        }
        let name = URL(fileURLWithPath: envelope.cwd).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}

/// The last few notifications, newest first.
public struct ActivityLog: Equatable, Sendable {
    public static let capacity = 4

    public private(set) var entries: [ActivityLogEntry] = []

    public init() {}

    /// Rebuilds a log from saved entries. A request that was still open
    /// can't be answered after a restart, so it comes back as missed.
    public init(restoring saved: [ActivityLogEntry]) {
        entries = Array(saved.prefix(Self.capacity)).map { entry in
            var entry = entry
            if entry.status == .pending { entry.status = .unhandled }
            return entry
        }
    }

    public mutating func record(_ entry: ActivityLogEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    public mutating func settle(id: String, outcome: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .handled(outcome)
    }

    /// A request that left Nudge without an answer still needs the user's eye.
    public mutating func markMissed(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .unhandled
    }
}

/// Saves the log as a small JSON file so it survives a restart. Only what the
/// log shows is kept: no commands (entries never hold them) and no terminal
/// session IDs.
public struct ActivityLogFile: Sendable {
    private struct Contents: Codable {
        var version: Int
        var entries: [ActivityLogEntry]
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> ActivityLog {
        guard let data = try? Data(contentsOf: url),
              let contents = try? JSONDecoder.activityLog.decode(Contents.self, from: data),
              contents.version == 1 else {
            return ActivityLog()
        }
        return ActivityLog(restoring: contents.entries)
    }

    public func save(_ log: ActivityLog) throws {
        let entries = log.entries.map { entry -> ActivityLogEntry in
            var entry = entry
            entry.host?.terminalSessionID = nil
            return entry
        }
        let data = try JSONEncoder.activityLog.encode(Contents(version: 1, entries: entries))
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private extension JSONEncoder {
    static var activityLog: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var activityLog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
