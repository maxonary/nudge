import Combine
import Foundation

enum AgentConnectorStatus: Equatable, Sendable {
    case notInstalled
    case installing
    case needsTrust
    case connected
    case failed(String)
}

private struct ClaudeRegistrySnapshot {
    let state: ClaudeConnectorRegistryState
    let installPath: String?
    let enablement: ClaudePluginEnablement
}

@MainActor
final class AgentConnectorManager: ObservableObject {
    static let shared = AgentConnectorManager()
    static let codexTrustInstruction = "In Codex /hooks öffnen und Nudge vertrauen"

    @Published private(set) var claudeCodeStatus: AgentConnectorStatus = .notInstalled
    @Published private(set) var codexStatus: AgentConnectorStatus = .notInstalled

    private let homeDirectory: URL
    private let bundle: Bundle
    private let retryStore: AgentConnectorRetryStore

    private var bridgeDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Nudge/AgentBridge", isDirectory: true)
    }

    private var stableHelperURL: URL {
        bridgeDirectory.appendingPathComponent("nudge-agent-hook")
    }

    private var claudeMarketplaceURL: URL {
        bridgeDirectory.appendingPathComponent("ClaudeMarketplace", isDirectory: true)
    }

    private var codexHooksURL: URL {
        homeDirectory.appendingPathComponent(".codex/hooks.json")
    }

    private var claudePluginRegistryURL: URL {
        homeDirectory.appendingPathComponent(".claude/plugins/installed_plugins.json")
    }

    private var claudeMarketplaceRegistryURL: URL {
        homeDirectory.appendingPathComponent(".claude/plugins/known_marketplaces.json")
    }

    private var claudeSettingsURL: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json")
    }

    private init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard
    ) {
        self.homeDirectory = homeDirectory
        self.bundle = bundle
        self.retryStore = AgentConnectorRetryStore(defaults: userDefaults)
        refresh()
    }

    func status(for source: AgentSource) -> AgentConnectorStatus {
        switch source {
        case .claudeCode:
            claudeCodeStatus
        case .codex:
            codexStatus
        }
    }

    func mutation(for source: AgentSource) -> AgentConnectorMutation {
        switch status(for: source) {
        case .connected, .needsTrust:
            return .disconnect
        case .notInstalled:
            return .connect
        case .installing, .failed:
            return retryStore.pendingMutation(for: source) ?? .connect
        }
    }

    func requiresManualConnectorRepair(for source: AgentSource) -> Bool {
        guard source == .claudeCode,
              case .failed = status(for: source)
        else { return false }

        guard (try? bundledHelperData()) != nil else { return true }
        guard let registry = try? claudeRegistrySnapshot() else { return true }
        if case .conflict = registry.state.marketplace { return true }
        return registry.state.pluginInstalledForUser
            && registry.state.marketplace == .owned
            && cachedClaudePluginRootURL(for: registry) == nil
    }

    func refresh() {
        setRefreshedStatus(refreshedClaudeStatus(), for: .claudeCode)
        setRefreshedStatus(refreshedCodexStatus(), for: .codex)
    }

    func connect(_ source: AgentSource) async {
        guard status(for: source) != .installing else { return }
        retryStore.begin(.connect, for: source)
        setStatus(.installing, for: source)

        do {
            let helperData = try bundledHelperData()
            switch source {
            case .claudeCode:
                let registry = try claudeRegistrySnapshot()
                guard let plan = registry.state.connectPlan else {
                    throw marketplaceConflictError(for: registry.state.marketplace)
                }
                let shouldEnablePlugin = registry.enablement == .disabled
                let needsCommand = plan.addMarketplace || plan.installPlugin || shouldEnablePlugin
                let executable = needsCommand ? try discoverClaudeExecutable() : nil
                let marketplaceURL = claudeMarketplaceURL
                let helperURL = stableHelperURL
                let installedPluginFiles = nudgeClaudeInstalledPluginFiles(
                    helperData: helperData
                )
                let cachedPluginRootURL = cachedClaudePluginRootURL(for: registry)
                let repairCachedPlugin = cachedPluginRootURL.map {
                    !agentFilesAreCurrent(
                        beneath: $0,
                        expectedFiles: installedPluginFiles,
                        executablePaths: ["bin/nudge_agent_hook.py"]
                    )
                } ?? false
                try await Task.detached(priority: .userInitiated) {
                    try installStableHelper(helperData, at: helperURL)
                    try writeClaudePluginFiles(helperData: helperData, beneath: marketplaceURL)
                    if repairCachedPlugin, let cachedPluginRootURL {
                        try writeAgentFiles(
                            installedPluginFiles,
                            beneath: cachedPluginRootURL,
                            executablePaths: ["bin/nudge_agent_hook.py"]
                        )
                    }
                    if plan.addMarketplace {
                        try runProcess(
                            executableURL: try requiredClaudeExecutable(executable),
                            arguments: [
                                "plugin", "marketplace", "add", marketplaceURL.path,
                                "--scope", "user"
                            ]
                        )
                    }
                    if plan.installPlugin {
                        try runProcess(
                            executableURL: try requiredClaudeExecutable(executable),
                            arguments: [
                                "plugin", "install", "nudge-agent-attention@nudge-local",
                                "--scope", "user"
                            ]
                        )
                    }
                    if shouldEnablePlugin {
                        try runProcess(
                            executableURL: try requiredClaudeExecutable(executable),
                            arguments: [
                                "plugin", "enable", "nudge-agent-attention@nudge-local",
                                "--scope", "user"
                            ]
                        )
                    }
                }.value
                setRefreshedStatus(refreshedClaudeStatus(), for: .claudeCode)

            case .codex:
                let helperURL = stableHelperURL
                let hooksURL = codexHooksURL
                try await Task.detached(priority: .userInitiated) {
                    try installStableHelper(helperData, at: helperURL)
                    try connectCodexHooks(at: hooksURL, helperPath: helperURL.path)
                }.value
                setRefreshedStatus(refreshedCodexStatus(), for: .codex)
            }
        } catch {
            setStatus(.failed(clearMessage(for: error)), for: source)
        }
    }

    func disconnect(_ source: AgentSource) async {
        guard status(for: source) != .installing else { return }
        retryStore.begin(.disconnect, for: source)
        setStatus(.installing, for: source)

        do {
            switch source {
            case .claudeCode:
                let registryState = try claudeRegistrySnapshot().state
                let plan = registryState.disconnectPlan
                guard plan.uninstallPlugin || plan.removeMarketplace else {
                    setRefreshedStatus(
                        disconnectedClaudeStatus(marketplace: registryState.marketplace),
                        for: .claudeCode
                    )
                    return
                }
                let executable = try discoverClaudeExecutable()
                let failures = await Task.detached(priority: .userInitiated) {
                    executeClaudeDisconnectPlan(
                        plan,
                        uninstallPlugin: {
                            try runProcess(
                                executableURL: executable,
                                arguments: [
                                    "plugin", "uninstall", "nudge-agent-attention@nudge-local",
                                    "--scope", "user", "--yes"
                                ]
                            )
                        },
                        removeMarketplace: {
                            try runProcess(
                                executableURL: executable,
                                arguments: [
                                    "plugin", "marketplace", "remove", "nudge-local",
                                    "--scope", "user"
                                ]
                            )
                        }
                    )
                }.value
                if !failures.isEmpty {
                    throw ConnectorRuntimeError.cleanupFailed(failures)
                }
                setRefreshedStatus(
                    disconnectedClaudeStatus(marketplace: registryState.marketplace),
                    for: .claudeCode
                )

            case .codex:
                let hooksURL = codexHooksURL
                try await Task.detached(priority: .userInitiated) {
                    try disconnectCodexHooks(at: hooksURL)
                }.value
                setRefreshedStatus(.notInstalled, for: .codex)
            }
        } catch {
            setStatus(.failed(clearMessage(for: error)), for: source)
        }
    }

    private func setStatus(_ status: AgentConnectorStatus, for source: AgentSource) {
        switch source {
        case .claudeCode:
            claudeCodeStatus = status
        case .codex:
            codexStatus = status
        }
    }

    private func setRefreshedStatus(_ status: AgentConnectorStatus, for source: AgentSource) {
        setStatus(status, for: source)
        switch status {
        case .notInstalled, .needsTrust, .connected:
            retryStore.clear(for: source)
        case .installing, .failed:
            break
        }
    }

    private func refreshedCodexStatus() -> AgentConnectorStatus {
        do {
            guard FileManager.default.fileExists(atPath: codexHooksURL.path) else {
                return .notInstalled
            }
            let data = try Data(contentsOf: codexHooksURL)
            guard !data.isEmpty else { return .notInstalled }
            let object = try codexHooksConfiguration(from: data)
            guard containsNudgeCodexHook(in: object) else { return .notInstalled }

            let helperData = try bundledHelperData()
            guard agentHelperIntegrity(
                at: stableHelperURL,
                expectedData: helperData
            ) == .current else {
                return .failed(
                    "Der Codex Hook ist unvollständig oder veraltet. Erneut verbinden repariert ihn."
                )
            }
            return .needsTrust
        } catch {
            return .failed(clearMessage(for: error))
        }
    }

    private func refreshedClaudeStatus() -> AgentConnectorStatus {
        do {
            let registry = try claudeRegistrySnapshot()
            switch (registry.state.pluginInstalledForUser, registry.state.marketplace) {
            case (true, .owned):
                guard registry.enablement != .disabled else {
                    return .failed(
                        "Das Nudge Plugin ist in Claude Code deaktiviert. Erneut verbinden aktiviert es."
                    )
                }
                let helperData = try bundledHelperData()
                let sourcePluginFiles = claudePluginFiles(helperData: helperData)
                let installedPluginFiles = nudgeClaudeInstalledPluginFiles(
                    helperData: helperData
                )
                guard agentFilesAreCurrent(
                    beneath: claudeMarketplaceURL,
                    expectedFiles: sourcePluginFiles,
                    executablePaths: [
                        "nudge-agent-attention/bin/nudge_agent_hook.py"
                    ]
                ) else {
                    return .failed(
                        "Das Claude Plugin ist unvollständig oder veraltet. Erneut verbinden repariert es."
                    )
                }
                guard let cachedPluginRootURL = cachedClaudePluginRootURL(for: registry) else {
                    return .failed(
                        "Claudes Nudge-Installationspfad ist nicht vertrauenswürdig. Nudge hat ihn nicht verändert; bitte das Plugin in Claude Code manuell prüfen."
                    )
                }
                guard agentFilesAreCurrent(
                    beneath: cachedPluginRootURL,
                    expectedFiles: installedPluginFiles,
                    executablePaths: ["bin/nudge_agent_hook.py"]
                ) else {
                    return .failed(
                        "Das Claude Plugin ist unvollständig oder veraltet. Erneut verbinden repariert es."
                    )
                }
                return .connected
            case (false, .absent):
                return .notInstalled
            case (_, .conflict):
                return .failed(clearMessage(for: marketplaceConflictError(
                    for: registry.state.marketplace
                )))
            default:
                return .failed(
                    "Claude ist nur teilweise verbunden. Erneut verbinden oder trennen."
                )
            }
        } catch {
            return .failed("Claude Plugin-Status konnte nicht gelesen werden: \(error.localizedDescription)")
        }
    }

    private func claudeRegistrySnapshot() throws -> ClaudeRegistrySnapshot {
        let installedPlugins = try readClaudeRegistry(
            at: claudePluginRegistryURL,
            name: "installed_plugins.json"
        )
        let knownMarketplaces = try readClaudeRegistry(
            at: claudeMarketplaceRegistryURL,
            name: "known_marketplaces.json"
        )
        let settings = try readClaudeRegistry(at: claudeSettingsURL, name: "settings.json")
        return ClaudeRegistrySnapshot(
            state: ClaudeConnectorRegistryState(
                pluginInstalledForUser: nudgeClaudePluginIsInstalledForUser(
                    in: installedPlugins
                ),
                marketplace: nudgeClaudeMarketplaceRegistration(
                    in: knownMarketplaces,
                    expectedInstallPath: claudeMarketplaceURL.path
                )
            ),
            installPath: nudgeClaudeUserPluginInstallPath(in: installedPlugins),
            enablement: nudgeClaudePluginEnablement(in: settings)
        )
    }

    private func cachedClaudePluginRootURL(for registry: ClaudeRegistrySnapshot) -> URL? {
        guard registry.state.marketplace == .owned else { return nil }
        guard let installPath = registry.installPath else { return nil }
        guard let helperURL = nudgeClaudeCachedHelperURL(
            installPath: installPath,
            homeDirectory: homeDirectory
        ) else { return nil }
        return helperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readClaudeRegistry(at url: URL, name: String) throws -> Any {
        guard FileManager.default.fileExists(atPath: url.path) else { return [String: Any]() }
        do {
            let data = try Data(contentsOf: url)
            let object = try JSONSerialization.jsonObject(with: data)
            guard object is [String: Any] else {
                throw ConnectorRuntimeError.invalidClaudeRegistry(name)
            }
            return object
        } catch let error as ConnectorRuntimeError {
            throw error
        } catch {
            throw ConnectorRuntimeError.invalidClaudeRegistry(name)
        }
    }

    private func marketplaceConflictError(
        for registration: ClaudeMarketplaceRegistration
    ) -> ConnectorRuntimeError {
        guard case let .conflict(actualPath) = registration else {
            return .invalidClaudeRegistry("known_marketplaces.json")
        }
        return .marketplaceConflict(actualPath: actualPath)
    }

    private func disconnectedClaudeStatus(
        marketplace: ClaudeMarketplaceRegistration
    ) -> AgentConnectorStatus {
        guard case .conflict = marketplace else { return .notInstalled }
        return .failed(clearMessage(for: marketplaceConflictError(for: marketplace)))
    }

    private func bundledHelperData() throws -> Data {
        let candidates = [
            bundle.url(forResource: "nudge_agent_hook", withExtension: "py"),
            bundle.url(
                forResource: "nudge_agent_hook",
                withExtension: "py",
                subdirectory: "AgentAttention/Resources"
            )
        ]
        guard let sourceURL = candidates.compactMap({ $0 }).first else {
            throw ConnectorRuntimeError.helperMissing
        }
        return try Data(contentsOf: sourceURL)
    }

    private func discoverClaudeExecutable() throws -> URL {
        let candidates = [
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            homeDirectory.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude")
        ]
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw ConnectorRuntimeError.claudeExecutableMissing
        }
        return executable
    }

    private func clearMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

private enum ConnectorRuntimeError: LocalizedError {
    case helperMissing
    case claudeExecutableMissing
    case invalidClaudeRegistry(String)
    case marketplaceConflict(actualPath: String?)
    case unsafeManagedPath(String)
    case commandFailed(name: String, status: Int32, output: String)
    case cleanupFailed([ClaudeCleanupFailure])

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "Der gebündelte Nudge Agent Hook fehlt. Bitte Nudge neu installieren."
        case .claudeExecutableMissing:
            return "Claude Code wurde an keinem unterstützten Installationspfad gefunden."
        case let .invalidClaudeRegistry(name):
            return "Claude Registry \(name) ist ungültig. Nudge hat nichts verändert."
        case let .marketplaceConflict(actualPath):
            if let actualPath {
                return "Claude Marketplace nudge-local gehört zu einem anderen Pfad (\(actualPath)). Nudge hat nichts verändert."
            } else {
                return "Claude Marketplace nudge-local hat keinen gültigen Installationspfad. Nudge hat nichts verändert."
            }
        case let .unsafeManagedPath(path):
            return "Nudge hat den unsicheren Plugin-Pfad \(path) nicht verändert."
        case let .commandFailed(name, status, output):
            if output.isEmpty {
                return "Claude-Befehl \(name) ist mit Status \(status) fehlgeschlagen."
            } else {
                return "Claude-Befehl \(name) ist mit Status \(status) fehlgeschlagen: \(output)"
            }
        case let .cleanupFailed(failures):
            let details = failures.map { failure in
                "\(failure.action.rawValue): \(failure.message)"
            }.joined(separator: "; ")
            return "Claude konnte nicht vollständig getrennt werden: \(details)"
        }
    }
}

private func requiredClaudeExecutable(_ executable: URL?) throws -> URL {
    guard let executable else { throw ConnectorRuntimeError.claudeExecutableMissing }
    return executable
}

private func installStableHelper(_ data: Data, at helperURL: URL) throws {
    try FileManager.default.createDirectory(
        at: helperURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try atomicWrite(data, to: helperURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: helperURL.path
    )
}

private func writeClaudePluginFiles(helperData: Data, beneath rootURL: URL) throws {
    try writeAgentFiles(
        claudePluginFiles(helperData: helperData),
        beneath: rootURL,
        executablePaths: ["nudge-agent-attention/bin/nudge_agent_hook.py"]
    )
}

private func writeAgentFiles(
    _ files: [String: Data],
    beneath rootURL: URL,
    executablePaths: Set<String>
) throws {
    for (relativePath, data) in files.sorted(by: { $0.key < $1.key }) {
        guard let destination = agentManagedFileURL(relativePath, beneath: rootURL) else {
            throw ConnectorRuntimeError.unsafeManagedPath(relativePath)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try atomicWrite(data, to: destination)
        if executablePaths.contains(relativePath) {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )
        }
    }
}

private func connectCodexHooks(at hooksURL: URL, helperPath: String) throws {
    let existingData = FileManager.default.fileExists(atPath: hooksURL.path)
        ? try Data(contentsOf: hooksURL)
        : nil
    let existing = try codexHooksConfiguration(from: existingData)
    let connected = addingNudgeCodexHooks(to: existing, helperPath: helperPath)
    let data = try JSONSerialization.data(
        withJSONObject: connected,
        options: [.prettyPrinted, .sortedKeys]
    )

    try FileManager.default.createDirectory(
        at: hooksURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try atomicWrite(data, to: hooksURL)
}

private func disconnectCodexHooks(at hooksURL: URL) throws {
    guard FileManager.default.fileExists(atPath: hooksURL.path) else { return }
    let data = try Data(contentsOf: hooksURL)
    guard !data.isEmpty else { return }

    let existing = try codexHooksConfiguration(from: data)
    guard containsNudgeCodexHook(in: existing) else { return }
    let disconnected = removingNudgeCodexHooks(from: existing)
    let updatedData = try JSONSerialization.data(
        withJSONObject: disconnected,
        options: [.prettyPrinted, .sortedKeys]
    )
    try atomicWrite(updatedData, to: hooksURL)
}

private func atomicWrite(_ data: Data, to destination: URL) throws {
    let fileManager = FileManager.default
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
        ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
    )
    do {
        try data.write(to: temporary, options: .withoutOverwriting)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    } catch {
        try? fileManager.removeItem(at: temporary)
        throw error
    }
}

private func runProcess(executableURL: URL, arguments: [String]) throws {
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    try process.run()
    let outputData = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let output = String(decoding: outputData.prefix(4_096), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw ConnectorRuntimeError.commandFailed(
            name: arguments.prefix(3).joined(separator: " "),
            status: process.terminationStatus,
            output: output
        )
    }
}

private func containsNudgeCodexHook(in object: Any) -> Bool {
    guard let root = object as? [String: Any],
          let events = root["hooks"] as? [String: Any]
    else { return false }

    return events.values.contains { value in
        guard let groups = value as? [[String: Any]] else { return false }
        return groups.contains { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
            return hooks.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.hasSuffix("# com.nudge.max.agent-hook")
            }
        }
    }
}
