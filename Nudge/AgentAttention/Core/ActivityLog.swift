import Foundation

/// One recent notification shown in the notch's short log.
public struct ActivityLogEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case completion
        case question
        case approval
        case nudge
    }

    public enum Status: Equatable, Sendable {
        /// A live agent request that can still be answered in Nudge.
        case pending
        /// Shown, but nobody acted on it yet.
        case unhandled
        /// Dealt with; the outcome says how ("Erlaubt", "Im Agent", "Gesehen").
        case handled(String)
    }

    public let id: String
    public let kind: Kind
    public var title: String
    public var detail: String?
    public var source: AgentSource?
    public var host: AgentHost?
    public var sender: String?
    public let date: Date
    public var status: Status

    public init(
        id: String,
        kind: Kind,
        title: String,
        detail: String? = nil,
        source: AgentSource? = nil,
        host: AgentHost? = nil,
        sender: String? = nil,
        date: Date,
        status: Status
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
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

/// The last few notifications, newest first. Kept in memory only.
public struct ActivityLog: Equatable, Sendable {
    public static let capacity = 4

    public private(set) var entries: [ActivityLogEntry] = []

    public init() {}

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
