import Foundation

/// Remembers that Nudge itself is about to bring an app forward, so the
/// activation that follows isn't mistaken for the user returning to it.
public struct ExpectedActivation: Equatable, Sendable {
    /// How long after `expect` the matching activation still counts as ours.
    public static let window: TimeInterval = 2

    private struct Expectation: Equatable, Sendable {
        let processIdentifier: Int32
        let date: Date
    }

    private var pending: Expectation?

    public init() {}

    /// A later call replaces an earlier one.
    public mutating func expect(processIdentifier: Int32, at now: Date) {
        pending = Expectation(processIdentifier: processIdentifier, date: now)
    }

    /// True exactly once for the expected app within `window` seconds; that
    /// expectation is then forgotten. Other apps return false and leave the
    /// expectation in place. Expired expectations return false and are cleared.
    public mutating func consume(processIdentifier: Int32, at now: Date) -> Bool {
        guard let pending, pending.processIdentifier == processIdentifier else { return false }
        self.pending = nil
        return now.timeIntervalSince(pending.date) <= Self.window
    }
}
