import Foundation

public enum ConnectorConfigurationError: Error, Equatable, LocalizedError {
    case malformedCodexHooks

    public var errorDescription: String? {
        switch self {
        case .malformedCodexHooks:
            "Codex hooks.json ist ungültig. Die Datei wurde nicht verändert."
        }
    }
}

private let nudgeHookMarker = "# com.nudge.max.agent-hook"
private let claudePluginDescription = "Routes Claude Code attention events to Nudge."

public func codexHooksConfiguration(from data: Data?) throws -> Any {
    guard let data, !data.isEmpty,
          !data.allSatisfy({ $0 == 0x09 || $0 == 0x0A || $0 == 0x0D || $0 == 0x20 })
    else {
        return ["hooks": [String: Any]()]
    }

    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ConnectorConfigurationError.malformedCodexHooks
    }

    guard let root = object as? [String: Any] else {
        throw ConnectorConfigurationError.malformedCodexHooks
    }
    if let hooks = root["hooks"], !(hooks is [String: Any]) {
        throw ConnectorConfigurationError.malformedCodexHooks
    }

    let events = root["hooks"] as? [String: Any] ?? [:]
    for eventName in ["Stop", "PermissionRequest"] {
        if let groups = events[eventName], !(groups is [[String: Any]]) {
            throw ConnectorConfigurationError.malformedCodexHooks
        }
    }

    var normalized = root
    normalized["hooks"] = events
    return normalized
}

public func addingNudgeCodexHooks(to object: Any, helperPath: String) -> Any {
    guard var root = removingNudgeCodexHooks(from: object) as? [String: Any],
          var events = root["hooks"] as? [String: Any]
    else { return object }

    let command = "\(shellQuoted(helperPath)) codex \(nudgeHookMarker)"
    appendCodexHook(
        event: "Stop",
        matcher: nil,
        timeout: 1,
        command: command,
        to: &events
    )
    appendCodexHook(
        event: "PermissionRequest",
        matcher: "*",
        timeout: 86_400,
        command: command,
        to: &events
    )
    root["hooks"] = events
    return root
}

public func removingNudgeCodexHooks(from object: Any) -> Any {
    guard var root = object as? [String: Any],
          var events = root["hooks"] as? [String: Any]
    else { return object }

    for (eventName, value) in events {
        guard let groups = value as? [[String: Any]] else { continue }
        let retainedGroups = groups.compactMap { group -> [String: Any]? in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return group }
            let retainedHooks = hooks.filter { hook in
                guard let command = hook["command"] as? String else { return true }
                return !command.hasSuffix(nudgeHookMarker)
            }
            guard !retainedHooks.isEmpty else { return nil }

            var retainedGroup = group
            retainedGroup["hooks"] = retainedHooks
            return retainedGroup
        }

        if retainedGroups.isEmpty {
            events.removeValue(forKey: eventName)
        } else {
            events[eventName] = retainedGroups
        }
    }

    root["hooks"] = events
    return root
}

public func claudePluginFiles(helperData: Data) -> [String: Data] {
    let command = "${CLAUDE_PLUGIN_ROOT}/bin/nudge_agent_hook.py claude"
    let marketplace: [String: Any] = [
        "name": "nudge-local",
        "description": "Local Nudge integrations for coding agents.",
        "owner": ["name": "Nudge"],
        "plugins": [[
            "name": "nudge-agent-attention",
            "source": "./nudge-agent-attention",
            "description": claudePluginDescription,
            "version": "0.1.0"
        ]]
    ]
    let plugin: [String: Any] = [
        "name": "nudge-agent-attention",
        "description": claudePluginDescription,
        "version": "0.1.0",
        "author": ["name": "Nudge"]
    ]
    let hooks: [String: Any] = [
        "description": claudePluginDescription,
        "hooks": [
            "Stop": [[
                "hooks": [["type": "command", "command": command, "timeout": 1]]
            ]],
            "PreToolUse": [[
                "matcher": "AskUserQuestion",
                "hooks": [["type": "command", "command": command, "timeout": 86_400]]
            ]],
            "PermissionRequest": [[
                "matcher": "*",
                "hooks": [["type": "command", "command": command, "timeout": 86_400]]
            ]]
        ]
    ]

    return [
        ".claude-plugin/marketplace.json": encodedJSON(marketplace),
        "nudge-agent-attention/.claude-plugin/plugin.json": encodedJSON(plugin),
        "nudge-agent-attention/hooks/hooks.json": encodedJSON(hooks),
        "nudge-agent-attention/bin/nudge_agent_hook.py": helperData
    ]
}

private func appendCodexHook(
    event: String,
    matcher: String?,
    timeout: Int,
    command: String,
    to events: inout [String: Any]
) {
    var group: [String: Any] = [
        "hooks": [[
            "type": "command",
            "command": command,
            "timeout": timeout
        ]]
    ]
    if let matcher {
        group["matcher"] = matcher
    }

    var groups = events[event] as? [[String: Any]] ?? []
    groups.append(group)
    events[event] = groups
}

private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func encodedJSON(_ object: Any) -> Data {
    // All objects above are made exclusively from JSON-compatible literals.
    try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}
