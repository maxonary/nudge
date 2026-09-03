import Combine
import Foundation

enum AgentConnectorStatus: Equatable, Sendable {
    case notInstalled
    case installing
    case needsTrust
    case connected
    case failed(String)
}

@MainActor
final class AgentConnectorManager: ObservableObject {
    static let shared = AgentConnectorManager()
    static let codexTrustInstruction = "In Codex /hooks öffnen und Nudge vertrauen"

    @Published private(set) var claudeCodeStatus: AgentConnectorStatus = .notInstalled
    @Published private(set) var codexStatus: AgentConnectorStatus = .notInstalled

    private let homeDirectory: URL
    private let bundle: Bundle

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

    private init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundle: Bundle = .main
    ) {
        self.homeDirectory = homeDirectory
        self.bundle = bundle
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

    func refresh() {
        claudeCodeStatus = refreshedClaudeStatus()
        codexStatus = refreshedCodexStatus()
    }

    func connect(_ source: AgentSource) async {
        setStatus(.installing, for: source)

        do {
            let helperData = try bundledHelperData()
            switch source {
            case .claudeCode:
                let executable = try discoverClaudeExecutable()
                let marketplaceURL = claudeMarketplaceURL
                let helperURL = stableHelperURL
                try await Task.detached(priority: .userInitiated) {
                    try installStableHelper(helperData, at: helperURL)
                    try writeClaudePluginFiles(helperData: helperData, beneath: marketplaceURL)
                    try runProcess(
                        executableURL: executable,
                        arguments: [
                            "plugin", "marketplace", "add", marketplaceURL.path,
                            "--scope", "user"
                        ]
                    )
                    try runProcess(
                        executableURL: executable,
                        arguments: [
                            "plugin", "install", "nudge-agent-attention@nudge-local",
                            "--scope", "user", "--yes"
                        ]
                    )
                }.value
                claudeCodeStatus = .connected

            case .codex:
                let helperURL = stableHelperURL
                let hooksURL = codexHooksURL
                try await Task.detached(priority: .userInitiated) {
                    try installStableHelper(helperData, at: helperURL)
                    try connectCodexHooks(at: hooksURL, helperPath: helperURL.path)
                }.value
                codexStatus = .needsTrust
            }
        } catch {
            setStatus(.failed(clearMessage(for: error)), for: source)
        }
    }

    func disconnect(_ source: AgentSource) async {
        setStatus(.installing, for: source)

        do {
            switch source {
            case .claudeCode:
                let executable = try discoverClaudeExecutable()
                try await Task.detached(priority: .userInitiated) {
                    try runProcess(
                        executableURL: executable,
                        arguments: [
                            "plugin", "uninstall", "nudge-agent-attention@nudge-local",
                            "--scope", "user", "--yes"
                        ]
                    )
                    try runProcess(
                        executableURL: executable,
                        arguments: [
                            "plugin", "marketplace", "remove", "nudge-local",
                            "--scope", "user"
                        ]
                    )
                }.value
                claudeCodeStatus = .notInstalled

            case .codex:
                let hooksURL = codexHooksURL
                try await Task.detached(priority: .userInitiated) {
                    try disconnectCodexHooks(at: hooksURL)
                }.value
                codexStatus = .notInstalled
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

    private func refreshedCodexStatus() -> AgentConnectorStatus {
        do {
            guard FileManager.default.fileExists(atPath: codexHooksURL.path) else {
                return .notInstalled
            }
            let data = try Data(contentsOf: codexHooksURL)
            guard !data.isEmpty else { return .notInstalled }
            let object = try codexHooksConfiguration(from: data)
            return containsNudgeCodexHook(in: object) ? .needsTrust : .notInstalled
        } catch {
            return .failed(clearMessage(for: error))
        }
    }

    private func refreshedClaudeStatus() -> AgentConnectorStatus {
        do {
            guard FileManager.default.fileExists(atPath: claudePluginRegistryURL.path) else {
                return .notInstalled
            }
            let data = try Data(contentsOf: claudePluginRegistryURL)
            let object = try JSONSerialization.jsonObject(with: data)
            return containsString("nudge-agent-attention@nudge-local", in: object)
                ? .connected
                : .notInstalled
        } catch {
            return .failed("Claude Plugin-Status konnte nicht gelesen werden: \(error.localizedDescription)")
        }
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
    case commandFailed(name: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            "Der gebündelte Nudge Agent Hook fehlt. Bitte Nudge neu installieren."
        case .claudeExecutableMissing:
            "Claude Code wurde an keinem unterstützten Installationspfad gefunden."
        case let .commandFailed(name, status, output):
            if output.isEmpty {
                "Claude-Befehl \(name) ist mit Status \(status) fehlgeschlagen."
            } else {
                "Claude-Befehl \(name) ist mit Status \(status) fehlgeschlagen: \(output)"
            }
        }
    }
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
    for (relativePath, data) in claudePluginFiles(helperData: helperData).sorted(by: { $0.key < $1.key }) {
        let destination = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try atomicWrite(data, to: destination)
        if relativePath.hasSuffix("/bin/nudge_agent_hook.py") {
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

private func containsString(_ needle: String, in object: Any) -> Bool {
    if let string = object as? String {
        return string == needle
    }
    if let array = object as? [Any] {
        return array.contains { containsString(needle, in: $0) }
    }
    if let dictionary = object as? [String: Any] {
        return dictionary.keys.contains(needle)
            || dictionary.values.contains { containsString(needle, in: $0) }
    }
    return false
}
