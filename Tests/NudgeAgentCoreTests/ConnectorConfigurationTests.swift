import Foundation
import Testing
@testable import NudgeAgentCore

struct ConnectorConfigurationTests {
    @Test
    func addingCodexHooksPreservesForeignGroupsAndIsIdempotent() throws {
        let existing = try jsonObject(
            """
            {
              "futureSetting": true,
              "hooks": {
                "Stop": [
                  {"matcher": "foreign", "hooks": [{"type": "command", "command": "mine", "timeout": 7}]}
                ],
                "SessionStart": [
                  {"hooks": [{"type": "command", "command": "also-mine"}]}
                ]
              }
            }
            """
        )

        let once = addingNudgeCodexHooks(to: existing, helperPath: "/stable/nudge-hook")
        let twice = addingNudgeCodexHooks(to: once, helperPath: "/stable/nudge-hook")

        #expect(try canonicalJSONData(once) == canonicalJSONData(twice))
        let text = try jsonString(once)
        #expect(text.contains("mine"))
        #expect(text.contains("also-mine"))
        #expect(text.contains("futureSetting"))
        #expect(ownedHookCommands(in: once).count == 2)
    }

    @Test
    func addingCodexHooksUsesRequiredEventsMatchersAndTimeouts() throws {
        let added = addingNudgeCodexHooks(
            to: ["hooks": [String: Any]()],
            helperPath: "/stable/nudge-hook"
        )
        let root = try #require(added as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])
        let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
        let permissionGroups = try #require(hooks["PermissionRequest"] as? [[String: Any]])

        #expect(stopGroups.count == 1)
        #expect(stopGroups[0]["matcher"] == nil)
        #expect(try timeout(in: stopGroups[0]) == 1)
        #expect(permissionGroups.count == 1)
        #expect(permissionGroups[0]["matcher"] as? String == "*")
        #expect(try timeout(in: permissionGroups[0]) == 86_400)
    }

    @Test
    func removingCodexHooksRemovesOnlyOwnedEntries() throws {
        let foreign = try jsonObject(
            """
            {
              "hooks": {
                "Stop": [{"hooks": [
                  {"type": "command", "command": "mine"},
                  {"type": "command", "command": "echo com.nudge.max.agent-hook"}
                ]}],
                "PermissionRequest": [{"matcher": "Bash", "hooks": [
                  {"type": "command", "command": "approval-mine"}
                ]}]
              }
            }
            """
        )
        let connected = addingNudgeCodexHooks(to: foreign, helperPath: "/stable/nudge-hook")

        let removed = removingNudgeCodexHooks(from: connected)

        let text = try jsonString(removed)
        #expect(text.contains("mine"))
        #expect(text.contains("approval-mine"))
        #expect(text.contains("echo com.nudge.max.agent-hook"))
        #expect(!text.contains("# com.nudge.max.agent-hook"))
        #expect(ownedHookCommands(in: removed).isEmpty)
    }

    @Test
    func connectAndDisconnectPreserveForeignEmptyHookGroupsAndMetadata() throws {
        let existing = try jsonObject(
            """
            {
              "hooks": {
                "Stop": [{
                  "matcher": "foreign-empty",
                  "description": "Keep this group exactly as configured.",
                  "futureMetadata": {"enabled": true},
                  "hooks": []
                }]
              }
            }
            """
        )

        let connected = addingNudgeCodexHooks(to: existing, helperPath: "/stable/nudge-hook")
        let connectedText = try jsonString(connected)
        let disconnected = removingNudgeCodexHooks(from: connected)

        #expect(connectedText.contains("foreign-empty"))
        #expect(connectedText.contains("futureMetadata"))
        #expect(try canonicalJSONData(disconnected) == canonicalJSONData(existing))
    }

    @Test
    func missingAndEmptyCodexConfigurationCreateAnEmptyHooksRoot() throws {
        let missing = try codexHooksConfiguration(from: nil)
        let empty = try codexHooksConfiguration(from: Data())
        let whitespace = try codexHooksConfiguration(from: Data(" \n\t".utf8))
        let expected: [String: Any] = ["hooks": [String: Any]()]

        #expect(try canonicalJSONData(missing) == canonicalJSONData(expected))
        #expect(try canonicalJSONData(empty) == canonicalJSONData(expected))
        #expect(try canonicalJSONData(whitespace) == canonicalJSONData(expected))
    }

    @Test
    func malformedOrNonObjectCodexConfigurationIsRejected() {
        #expect(throws: ConnectorConfigurationError.self) {
            try codexHooksConfiguration(from: Data("not json".utf8))
        }
        #expect(throws: ConnectorConfigurationError.self) {
            try codexHooksConfiguration(from: Data("[]".utf8))
        }
        #expect(throws: ConnectorConfigurationError.self) {
            try codexHooksConfiguration(from: Data(#"{"hooks":[]}"#.utf8))
        }
    }

    @Test
    func codexCommandShellQuotesSpacesAndApostrophes() throws {
        let added = addingNudgeCodexHooks(
            to: ["hooks": [String: Any]()],
            helperPath: "/Users/Max O'Brien/Nudge hook"
        )

        #expect(ownedHookCommands(in: added) == [
            "'/Users/Max O'\\''Brien/Nudge hook' codex # com.nudge.max.agent-hook",
            "'/Users/Max O'\\''Brien/Nudge hook' codex # com.nudge.max.agent-hook"
        ])
    }

    @Test
    func claudeInstalledPluginParserRequiresExactUserEntryWithInstallPath() throws {
        let falsePositives = try jsonObject(
            """
            {
              "version": 2,
              "metadata": {
                "nudge-agent-attention@nudge-local": [
                  {"scope": "user", "installPath": "/metadata-only"}
                ]
              },
              "plugins": {
                "nudge-agent-attention@nudge-local": [
                  {"scope": "project", "installPath": "/project-copy"},
                  {"scope": "user", "installPath": ""}
                ]
              }
            }
            """
        )
        let installedForUser = try jsonObject(
            """
            {
              "version": 2,
              "plugins": {
                "nudge-agent-attention@nudge-local": [
                  {"scope": "project", "installPath": "/project-copy"},
                  {"scope": "user", "installPath": "/user-copy"}
                ]
              }
            }
            """
        )

        #expect(!nudgeClaudePluginIsInstalledForUser(in: falsePositives))
        #expect(nudgeClaudePluginIsInstalledForUser(in: installedForUser))
    }

    @Test
    func claudeMarketplaceParserUsesOnlyExactTopLevelOwnedPath() throws {
        let expectedPath = "/stable/ClaudeMarketplace"
        let metadataFalsePositive = try jsonObject(
            """
            {
              "version": 2,
              "metadata": {
                "nudge-local": {"installLocation": "/stable/ClaudeMarketplace"}
              }
            }
            """
        )
        let foreignSameName = try jsonObject(
            """
            {
              "version": 2,
              "nudge-local": {
                "source": {"source": "directory", "path": "/someone-else"},
                "installLocation": "/someone-else",
                "lastUpdated": "2026-09-03T10:00:00Z"
              }
            }
            """
        )
        let owned = try jsonObject(
            """
            {
              "version": 2,
              "nudge-local": {
                "source": {"source": "directory", "path": "/stable/ClaudeMarketplace"},
                "installLocation": "/stable/ClaudeMarketplace",
                "lastUpdated": "2026-09-03T10:00:00Z"
              }
            }
            """
        )

        #expect(nudgeClaudeMarketplaceRegistration(
            in: metadataFalsePositive,
            expectedInstallPath: expectedPath
        ) == .absent)
        #expect(nudgeClaudeMarketplaceRegistration(
            in: foreignSameName,
            expectedInstallPath: expectedPath
        ) == .conflict(actualPath: "/someone-else"))
        #expect(nudgeClaudeMarketplaceRegistration(
            in: owned,
            expectedInstallPath: expectedPath
        ) == .owned)
    }

    @Test
    func claudePlansAreIdempotentAndCoverPartialCleanup() {
        let absent = ClaudeConnectorRegistryState(
            pluginInstalledForUser: false,
            marketplace: .absent
        )
        let fullyInstalled = ClaudeConnectorRegistryState(
            pluginInstalledForUser: true,
            marketplace: .owned
        )
        let pluginOnly = ClaudeConnectorRegistryState(
            pluginInstalledForUser: true,
            marketplace: .absent
        )
        let marketplaceOnly = ClaudeConnectorRegistryState(
            pluginInstalledForUser: false,
            marketplace: .owned
        )
        let conflict = ClaudeConnectorRegistryState(
            pluginInstalledForUser: true,
            marketplace: .conflict(actualPath: "/someone-else")
        )

        #expect(absent.connectPlan == .init(addMarketplace: true, installPlugin: true))
        #expect(absent.disconnectPlan == .init(uninstallPlugin: false, removeMarketplace: false))
        #expect(fullyInstalled.connectPlan == .init(addMarketplace: false, installPlugin: false))
        #expect(fullyInstalled.disconnectPlan == .init(uninstallPlugin: true, removeMarketplace: true))
        #expect(pluginOnly.connectPlan == .init(addMarketplace: true, installPlugin: false))
        #expect(pluginOnly.disconnectPlan == .init(uninstallPlugin: true, removeMarketplace: false))
        #expect(marketplaceOnly.connectPlan == .init(addMarketplace: false, installPlugin: true))
        #expect(marketplaceOnly.disconnectPlan == .init(uninstallPlugin: false, removeMarketplace: true))
        #expect(conflict.connectPlan == nil)
        #expect(conflict.disconnectPlan == nil)
    }

    @Test
    func claudeDisconnectAttemptsBothOwnedCleanupActionsWhenEachFails() {
        let plan = ClaudeDisconnectPlan(uninstallPlugin: true, removeMarketplace: true)
        var attempts: [ClaudeCleanupAction] = []

        let failures = executeClaudeDisconnectPlan(
            plan,
            uninstallPlugin: {
                attempts.append(.uninstallPlugin)
                throw CleanupFixtureError(message: "uninstall failed")
            },
            removeMarketplace: {
                attempts.append(.removeMarketplace)
                throw CleanupFixtureError(message: "remove failed")
            }
        )

        #expect(attempts == [.uninstallPlugin, .removeMarketplace])
        #expect(failures == [
            .init(action: .uninstallPlugin, message: "uninstall failed"),
            .init(action: .removeMarketplace, message: "remove failed")
        ])
    }

    @Test
    func claudePluginFilesContainExactManifestsHooksAndHelper() throws {
        let helper = Data("helper".utf8)
        let files = claudePluginFiles(helperData: helper)

        #expect(Set(files.keys) == [
            ".claude-plugin/marketplace.json",
            "nudge-agent-attention/.claude-plugin/plugin.json",
            "nudge-agent-attention/hooks/hooks.json",
            "nudge-agent-attention/bin/nudge_agent_hook.py"
        ])
        #expect(files["nudge-agent-attention/bin/nudge_agent_hook.py"] == helper)

        let expectedMarketplace = try jsonObject(
            """
            {
              "name": "nudge-local",
              "description": "Local Nudge integrations for coding agents.",
              "owner": {"name": "Nudge"},
              "plugins": [{
                "name": "nudge-agent-attention",
                "source": "./nudge-agent-attention",
                "description": "Routes Claude Code attention events to Nudge.",
                "version": "0.1.0"
              }]
            }
            """
        )
        let expectedPlugin = try jsonObject(
            """
            {
              "name": "nudge-agent-attention",
              "description": "Routes Claude Code attention events to Nudge.",
              "version": "0.1.0",
              "author": {"name": "Nudge"}
            }
            """
        )
        let expectedHooks = try jsonObject(
            """
            {
              "description": "Routes Claude Code attention events to Nudge.",
              "hooks": {
                "Stop": [{"hooks": [{
                  "type": "command",
                  "command": "${CLAUDE_PLUGIN_ROOT}/bin/nudge_agent_hook.py claude",
                  "timeout": 1
                }]}],
                "PreToolUse": [{"matcher": "AskUserQuestion", "hooks": [{
                  "type": "command",
                  "command": "${CLAUDE_PLUGIN_ROOT}/bin/nudge_agent_hook.py claude",
                  "timeout": 86400
                }]}],
                "PermissionRequest": [{"matcher": "*", "hooks": [{
                  "type": "command",
                  "command": "${CLAUDE_PLUGIN_ROOT}/bin/nudge_agent_hook.py claude",
                  "timeout": 86400
                }]}]
              }
            }
            """
        )

        #expect(try decodedJSON(in: files, at: ".claude-plugin/marketplace.json") == canonicalJSONData(expectedMarketplace))
        #expect(try decodedJSON(in: files, at: "nudge-agent-attention/.claude-plugin/plugin.json") == canonicalJSONData(expectedPlugin))
        #expect(try decodedJSON(in: files, at: "nudge-agent-attention/hooks/hooks.json") == canonicalJSONData(expectedHooks))
    }
}

private func jsonObject(_ string: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(string.utf8))
}

private func canonicalJSONData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonString(_ object: Any) throws -> String {
    String(decoding: try canonicalJSONData(object), as: UTF8.self)
}

private func decodedJSON(in files: [String: Data], at path: String) throws -> Data {
    let data = try #require(files[path])
    return try canonicalJSONData(JSONSerialization.jsonObject(with: data))
}

private func timeout(in group: [String: Any]) throws -> Int {
    let hooks = try #require(group["hooks"] as? [[String: Any]])
    let hook = try #require(hooks.first)
    return try #require(hook["timeout"] as? Int)
}

private func ownedHookCommands(in object: Any) -> [String] {
    guard let root = object as? [String: Any],
          let events = root["hooks"] as? [String: Any]
    else { return [] }

    return events.keys.sorted().flatMap { event -> [String] in
        guard let groups = events[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { group -> [String] in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return [] }
            return hooks.compactMap { hook in
                guard let command = hook["command"] as? String,
                      command.hasSuffix("# com.nudge.max.agent-hook")
                else { return nil }
                return command
            }
        }
    }
}

private struct CleanupFixtureError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
