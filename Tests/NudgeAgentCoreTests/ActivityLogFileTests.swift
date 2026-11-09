import Foundation
import Testing
@testable import NudgeAgentCore

struct ActivityLogFileTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nudge-activity-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("activity-log.json")
    }

    private func entry(_ id: String, status: ActivityLogEntry.Status) -> ActivityLogEntry {
        ActivityLogEntry(
            id: id,
            kind: .approval,
            title: "Claude Code möchte Bash nutzen",
            detail: "git push --force",
            source: .claudeCode,
            host: AgentHost(appName: "Conductor", bundleID: "com.conductor.app", terminalSessionID: "tty-7"),
            date: Date(timeIntervalSince1970: 1_800_000_000),
            status: status
        )
    }

    @Test
    func savedLogLoadsBackWithoutCommandsOrTerminalSessions() throws {
        let file = temporaryFile()
        var log = ActivityLog()
        log.record(entry("a", status: .handled("Erlaubt")))

        try ActivityLogFile(url: file).save(log)
        let loaded = ActivityLogFile(url: file).load()

        let restored = try #require(loaded.entries.first)
        #expect(restored.id == "a")
        #expect(restored.title == "Claude Code möchte Bash nutzen")
        #expect(restored.status == .handled("Erlaubt"))
        #expect(restored.date == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(restored.host?.bundleID == "com.conductor.app")
        #expect(restored.detail == nil)
        #expect(restored.host?.terminalSessionID == nil)

        let raw = try String(contentsOf: file, encoding: .utf8)
        #expect(!raw.contains("git push"))
    }

    @Test
    func requestThatWasOpenWhenNudgeQuitLoadsAsMissed() throws {
        let file = temporaryFile()
        var log = ActivityLog()
        log.record(entry("a", status: .pending))

        try ActivityLogFile(url: file).save(log)

        #expect(ActivityLogFile(url: file).load().entries.first?.status == .unhandled)
    }

    @Test
    func missingOrDamagedFileLoadsAnEmptyLog() throws {
        let file = temporaryFile()
        #expect(ActivityLogFile(url: file).load().entries.isEmpty)

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(ActivityLogFile(url: file).load().entries.isEmpty)
    }

    @Test
    func savedFileIsReadableOnlyByTheOwner() throws {
        let file = temporaryFile()
        try ActivityLogFile(url: file).save(ActivityLog())

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
