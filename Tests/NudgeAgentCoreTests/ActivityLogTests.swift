import Foundation
import Testing
@testable import NudgeAgentCore

struct ActivityLogTests {
    private func entry(_ id: String, kind: ActivityLogEntry.Kind = .completion, status: ActivityLogEntry.Status = .unhandled) -> ActivityLogEntry {
        ActivityLogEntry(id: id, kind: kind, title: id, date: Date(timeIntervalSince1970: 0), status: status)
    }

    @Test
    func newestEntryComesFirstAndLogKeepsOnlyTheCapacity() {
        var log = ActivityLog()
        for index in 1...6 {
            log.record(entry("e\(index)"))
        }

        #expect(log.entries.map(\.id) == ["e6", "e5", "e4", "e3"])
    }

    @Test
    func recordingAnExistingIDReplacesItAtTheTop() {
        var log = ActivityLog()
        log.record(entry("a"))
        log.record(entry("b"))
        log.record(entry("a", status: .pending))

        #expect(log.entries.map(\.id) == ["a", "b"])
        #expect(log.entries.first?.status == .pending)
    }

    @Test
    func settlingChangesOnlyTheMatchingEntry() {
        var log = ActivityLog()
        log.record(entry("a", kind: .approval, status: .pending))
        log.record(entry("b"))

        log.settle(id: "a", outcome: "Erlaubt")

        #expect(log.entries.first(where: { $0.id == "a" })?.status == .handled("Erlaubt"))
        #expect(log.entries.first(where: { $0.id == "b" })?.status == .unhandled)
    }

    @Test
    func handledEntriesAreDimmedAndOthersAreNot() {
        #expect(entry("a", status: .handled("Gesehen")).isDimmed)
        #expect(!entry("a", status: .unhandled).isDimmed)
        #expect(!entry("a", status: .pending).isDimmed)
    }

    @Test
    func pendingEntryThatWasNeverAnsweredBecomesUnhandledNotHandled() {
        var log = ActivityLog()
        log.record(entry("a", kind: .question, status: .pending))

        log.markMissed(id: "a")

        #expect(log.entries.first?.status == .unhandled)
    }
}
