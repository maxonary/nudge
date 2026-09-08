import Foundation

enum AgentConnectorMutation: String, Equatable, Sendable {
    case connect
    case disconnect
}

struct AgentConnectorRetryStore {
    private static let keyPrefix = "com.nudge.max.agent-connector.pending-mutation."

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func begin(_ mutation: AgentConnectorMutation, for source: AgentSource) {
        defaults.set(mutation.rawValue, forKey: key(for: source))
    }

    func pendingMutation(for source: AgentSource) -> AgentConnectorMutation? {
        guard let rawValue = defaults.string(forKey: key(for: source)) else { return nil }
        return AgentConnectorMutation(rawValue: rawValue)
    }

    func clear(for source: AgentSource) {
        defaults.removeObject(forKey: key(for: source))
    }

    private func key(for source: AgentSource) -> String {
        Self.keyPrefix + source.rawValue
    }
}

enum AgentHelperIntegrity: Equatable, Sendable {
    case missing
    case unreadable
    case notExecutable
    case contentMismatch
    case current
}

func agentHelperIntegrity(
    at url: URL,
    expectedData: Data,
    fileManager: FileManager = .default
) -> AgentHelperIntegrity {
    guard fileManager.fileExists(atPath: url.path) else { return .missing }
    guard let installedData = try? Data(contentsOf: url) else { return .unreadable }
    guard fileManager.isExecutableFile(atPath: url.path) else { return .notExecutable }
    guard installedData == expectedData else { return .contentMismatch }
    return .current
}

func nudgeClaudeUserPluginInstallPath(in object: Any) -> String? {
    guard let root = object as? [String: Any],
          let plugins = root["plugins"] as? [String: Any],
          let installations = plugins["nudge-agent-attention@nudge-local"] as? [[String: Any]]
    else { return nil }

    return installations.compactMap { installation in
        guard installation["scope"] as? String == "user",
              let installPath = installation["installPath"] as? String
        else { return nil }
        let trimmed = installPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }.first
}

enum ClaudePluginEnablement: Equatable, Sendable {
    case enabled
    case disabled
    case unspecified
}

func nudgeClaudePluginEnablement(in object: Any) -> ClaudePluginEnablement {
    guard let root = object as? [String: Any],
          let enabledPlugins = root["enabledPlugins"] as? [String: Any],
          let isEnabled = enabledPlugins["nudge-agent-attention@nudge-local"] as? Bool
    else { return .unspecified }

    return isEnabled ? .enabled : .disabled
}

func nudgeClaudeCachedHelperURL(
    installPath: String,
    homeDirectory: URL
) -> URL? {
    guard (installPath as NSString).isAbsolutePath else { return nil }

    let cacheBase = homeDirectory
        .appendingPathComponent(".claude/plugins/cache", isDirectory: true)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    let pluginCacheRoot = cacheBase
        .appendingPathComponent("nudge-local/nudge-agent-attention", isDirectory: true)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    let installedPlugin = URL(fileURLWithPath: installPath, isDirectory: true)
        .standardizedFileURL
        .resolvingSymlinksInPath()

    guard isStrictDescendant(pluginCacheRoot, of: cacheBase),
          isStrictDescendant(installedPlugin, of: pluginCacheRoot)
    else { return nil }

    return installedPlugin.appendingPathComponent("bin/nudge_agent_hook.py")
}

private func isStrictDescendant(_ candidate: URL, of directory: URL) -> Bool {
    candidate.path.hasPrefix(directory.path + "/")
}

func nudgeClaudeInstalledPluginFiles(helperData: Data) -> [String: Data] {
    let prefix = "nudge-agent-attention/"
    return Dictionary(uniqueKeysWithValues: claudePluginFiles(helperData: helperData).compactMap {
        path, data in
        guard path.hasPrefix(prefix) else { return nil }
        return (String(path.dropFirst(prefix.count)), data)
    })
}

func agentFilesAreCurrent(
    beneath rootURL: URL,
    expectedFiles: [String: Data],
    executablePaths: Set<String>,
    fileManager: FileManager = .default
) -> Bool {
    expectedFiles.allSatisfy { path, expectedData in
        guard let fileURL = agentManagedFileURL(path, beneath: rootURL),
              let installedData = try? Data(contentsOf: fileURL),
              installedData == expectedData
        else { return false }
        return !executablePaths.contains(path)
            || fileManager.isExecutableFile(atPath: fileURL.path)
    }
}

func agentManagedFileURL(_ relativePath: String, beneath rootURL: URL) -> URL? {
    guard !(relativePath as NSString).isAbsolutePath else { return nil }

    let lexicalRoot = rootURL.standardizedFileURL
    let lexicalCandidate = rootURL
        .appendingPathComponent(relativePath)
        .standardizedFileURL
    guard isStrictDescendant(lexicalCandidate, of: lexicalRoot) else { return nil }

    let resolvedRoot = lexicalRoot.resolvingSymlinksInPath()
    let resolvedParent = lexicalCandidate
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()
    let resolvedCandidate = lexicalCandidate.resolvingSymlinksInPath()
    guard isSameOrDescendant(resolvedParent, of: resolvedRoot),
          isStrictDescendant(resolvedCandidate, of: resolvedRoot)
    else { return nil }

    return lexicalCandidate
}

private func isSameOrDescendant(_ candidate: URL, of directory: URL) -> Bool {
    candidate.path == directory.path || isStrictDescendant(candidate, of: directory)
}
