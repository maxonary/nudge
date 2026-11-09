import Foundation
import Testing
@testable import NudgeAgentCore

struct ConnectorLifecycleTests {
    @Test
    func pendingMutationSurvivesStoreRecreationAndStaysSourceSpecific() throws {
        let suiteName = "ConnectorLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = AgentConnectorRetryStore(defaults: defaults)
        firstStore.begin(.disconnect, for: .claudeCode)

        let recreatedStore = AgentConnectorRetryStore(
            defaults: try #require(UserDefaults(suiteName: suiteName))
        )

        #expect(recreatedStore.pendingMutation(for: .claudeCode) == .disconnect)
        #expect(recreatedStore.pendingMutation(for: .codex) == nil)
    }

    @Test
    func clearingSettledMutationRemovesPersistedRetryDirection() throws {
        let suiteName = "ConnectorLifecycleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AgentConnectorRetryStore(defaults: defaults)
        store.begin(.connect, for: .codex)
        store.clear(for: .codex)

        let recreatedStore = AgentConnectorRetryStore(
            defaults: try #require(UserDefaults(suiteName: suiteName))
        )
        #expect(recreatedStore.pendingMutation(for: .codex) == nil)
    }

    @Test
    func helperIntegrityRejectsMissingAndNonExecutableFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectorLifecycleTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let helperURL = directory.appendingPathComponent("nudge-agent-hook")
        let expected = Data("expected helper".utf8)

        #expect(agentHelperIntegrity(at: helperURL, expectedData: expected) == .missing)

        try expected.write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: helperURL.path
        )
        #expect(agentHelperIntegrity(at: helperURL, expectedData: expected) == .notExecutable)
    }

    @Test
    func helperIntegrityRejectsDifferentBytesAndAcceptsExactExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectorLifecycleTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let helperURL = directory.appendingPathComponent("nudge-agent-hook")
        let expected = Data("expected helper".utf8)
        try Data("tampered helper".utf8).write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )

        #expect(agentHelperIntegrity(at: helperURL, expectedData: expected) == .contentMismatch)

        try expected.write(to: helperURL)
        #expect(agentHelperIntegrity(at: helperURL, expectedData: expected) == .current)
    }

    @Test
    func claudeInstallPathParserUsesOnlyExactUserPluginEntry() throws {
        let object = try JSONSerialization.jsonObject(with: Data(
            """
            {
              "metadata": {
                "nudge-agent-attention@nudge-local": [
                  {"scope": "user", "installPath": "/metadata-only"}
                ]
              },
              "plugins": {
                "nudge-agent-attention@nudge-local": [
                  {"scope": "project", "installPath": "/project-copy"},
                  {"scope": "user", "installPath": "  "},
                  {"scope": "user", "installPath": "/user-copy"}
                ]
              }
            }
            """.utf8
        ))

        #expect(nudgeClaudeUserPluginInstallPath(in: object) == "/user-copy")
        #expect(nudgeClaudeUserPluginInstallPath(in: ["plugins": [:]]) == nil)
    }

    @Test
    func claudeEnablementParserHonorsOnlyExactTopLevelBoolean() {
        #expect(nudgeClaudePluginEnablement(in: [
            "enabledPlugins": ["nudge-agent-attention@nudge-local": true]
        ]) == .enabled)
        #expect(nudgeClaudePluginEnablement(in: [
            "enabledPlugins": ["nudge-agent-attention@nudge-local": false]
        ]) == .disabled)
        #expect(nudgeClaudePluginEnablement(in: [
            "metadata": ["nudge-agent-attention@nudge-local": false]
        ]) == .unspecified)
        #expect(nudgeClaudePluginEnablement(in: [
            "enabledPlugins": ["nudge-agent-attention@nudge-local": "false"]
        ]) == .unspecified)
    }

    @Test
    func claudeCachedHelperPathAcceptsOnlyOfficialNudgeCacheDescendants() {
        let home = URL(fileURLWithPath: "/Users/Max", isDirectory: true)

        #expect(nudgeClaudeCachedHelperURL(
            installPath: "/Users/Max/.claude/plugins/cache/nudge-local/nudge-agent-attention/0.1.0",
            homeDirectory: home
        )?.path == "/Users/Max/.claude/plugins/cache/nudge-local/nudge-agent-attention/0.1.0/bin/nudge_agent_hook.py")
        #expect(nudgeClaudeCachedHelperURL(
            installPath: "/Users/Max/.claude/plugins/cache/nudge-local/nudge-agent-attention-evil/0.1.0",
            homeDirectory: home
        ) == nil)
        #expect(nudgeClaudeCachedHelperURL(
            installPath: "/Users/Max/Documents/not-a-cache",
            homeDirectory: home
        ) == nil)
        #expect(nudgeClaudeCachedHelperURL(
            installPath: "relative/cache/path",
            homeDirectory: home
        ) == nil)
    }

    @Test
    func claudeInstalledPluginIntegrityCoversManifestHooksHelperAndExecutableBit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectorLifecycleTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = nudgeClaudeInstalledPluginFiles(helperData: Data("helper".utf8))
        #expect(Set(expected.keys) == [
            ".claude-plugin/plugin.json",
            "hooks/hooks.json",
            "bin/nudge_agent_hook.py"
        ])

        for (path, data) in expected {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }

        #expect(!agentFilesAreCurrent(
            beneath: directory,
            expectedFiles: expected,
            executablePaths: ["bin/nudge_agent_hook.py"]
        ))

        let helperURL = directory.appendingPathComponent("bin/nudge_agent_hook.py")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )
        #expect(agentFilesAreCurrent(
            beneath: directory,
            expectedFiles: expected,
            executablePaths: ["bin/nudge_agent_hook.py"]
        ))

        try Data("changed hooks".utf8).write(
            to: directory.appendingPathComponent("hooks/hooks.json")
        )
        #expect(!agentFilesAreCurrent(
            beneath: directory,
            expectedFiles: expected,
            executablePaths: ["bin/nudge_agent_hook.py"]
        ))
    }

    @Test
    func managedPluginFilePathRejectsTraversalAndSymlinkEscape() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnectorLifecycleTests.\(UUID().uuidString)")
        let root = temporary.appendingPathComponent("plugin", isDirectory: true)
        let outside = temporary.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("hooks"),
            withDestinationURL: outside
        )
        defer { try? FileManager.default.removeItem(at: temporary) }

        #expect(agentManagedFileURL("bin/helper", beneath: root)?.path
            == root.appendingPathComponent("bin/helper").path)
        #expect(agentManagedFileURL("../outside/file", beneath: root) == nil)
        #expect(agentManagedFileURL("hooks/file", beneath: root) == nil)
    }
}
