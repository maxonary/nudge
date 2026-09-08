//
//  SettingsView.swift
//  Nudge
//

import AppKit
import Defaults
import ServiceManagement
import SwiftUI
import os

/// Thin wrapper over the modern `SMAppService` login-item API (macOS 13+).
enum LoginItem {
    private static let log = Logger(subsystem: "com.ontora.nudge", category: "loginitem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("login item toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            NudgeSettingsPane()
        }
        .frame(width: 540, height: 600)
    }
}

struct NudgeSettingsPane: View {
    @ObservedObject var identity = NudgeIdentity.shared
    @ObservedObject var teamSecret = NudgeTeamSecret.shared
    @ObservedObject var stats = NudgeStats.shared
    @ObservedObject var roster = NudgeRoster.shared
    @ObservedObject var connectorManager = AgentConnectorManager.shared
    @ObservedObject var agentAttention = AgentAttentionCenter.shared
    @Default(.nudgePlaySoundOnReceive) var playSoundOnReceive
    @Default(.nudgeShowBackupNotification) var showBackupNotification
    @Default(.klipyApiKey) var klipyApiKey

    @State private var nameDraft: String = NudgeIdentity.shared.current ?? ""
    @State private var nameError: String?
    @State private var showingPasswordSheet: Bool = false
    @State private var launchAtLogin: Bool = LoginItem.isEnabled

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                LoginItem.setEnabled(newValue)
                launchAtLogin = LoginItem.isEnabled
            }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Your name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveName)
                    Button("Save", action: saveName)
                        .disabled(
                            !NudgeIdentity.isValid(NudgeIdentity.sanitize(nameDraft)) ||
                            NudgeIdentity.sanitize(nameDraft) == identity.current
                        )
                }
                if let err = nameError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("This is what teammates see on their notch when you nudge them. 1–\(nudgeMaxNameLength) characters, no colons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    if teamSecret.hasPassword {
                        Label("Set", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Not set — pings won't work", systemImage: "lock.open.fill")
                            .foregroundStyle(.red)
                    }
                }
                Button("Change password…") {
                    showingPasswordSheet = true
                }
            } header: {
                Text("Team password")
            } footer: {
                Text("Everyone on your team must type the same password. It encrypts your pings and decides who's on the same team. Stored in Keychain, never sent over the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                let others = roster.others(excluding: identity.current)
                if others.isEmpty {
                    Text("No teammates seen yet. Send or wait for a hello — you'll appear here within a minute or two.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(others, id: \.self) { name in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                            Text(name)
                            Spacer()
                            if let seen = roster.teammates[name] {
                                Text(seen.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Known teammates")
            } footer: {
                Text("People who have said hello on this team password. Auto-refreshes every ~30 minutes per teammate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                let lb = stats.leaderboard()
                let allZero = lb.allSatisfy { $0.sends == 0 }
                if allZero {
                    Text("No nudges yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lb.enumerated()), id: \.element.peer) { idx, row in
                        HStack {
                            Text("\(idx + 1).")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 22, alignment: .leading)
                            Text(row.peer)
                                .fontWeight(row.peer == identity.current ? .semibold : .regular)
                            if row.peer == identity.current {
                                Text("(you)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Spacer()
                            Text("\(row.sends)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                let sent = stats.sentBreakdown()
                if !sent.isEmpty {
                    Divider()
                    Text("You sent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(sent, id: \.peer) { row in
                        HStack {
                            Text("→ \(row.peer)")
                            Spacer()
                            Text("\(row.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                let recv = stats.receivedBreakdown()
                if !recv.isEmpty {
                    Divider()
                    Text("You received")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(recv, id: \.peer) { row in
                        HStack {
                            Text("← \(row.peer)")
                            Spacer()
                            Text("\(row.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Leaderboard (all-time)")
            } footer: {
                Text("All-time totals. Each row is what that teammate has reported via their pings. Someone who hasn't pinged yet shows 0.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open Nudge at login", isOn: launchAtLoginBinding)
            } header: {
                Text("Startup")
            } footer: {
                Text("Automatically start Nudge when you log in to your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Play sound on receive", isOn: $playSoundOnReceive)
                Toggle("Show macOS notification (fallback)", isOn: $showBackupNotification)
            } header: {
                Text("Receive behavior")
            }

            Section {
                agentConnectorRow(.claudeCode)
                agentConnectorRow(.codex)
            } header: {
                Text("Agent-Integrationen")
            } footer: {
                Text("Verbindungen gelten für deinen macOS-Benutzer. Trennen entfernt nur die von Nudge registrierten Hooks und Plugins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SecureField("Klipy API key", text: $klipyApiKey)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("GIFs")
            } footer: {
                Text("A shared team key ships with the app, so GIFs work out of the box. Paste your own Klipy key here only if you want to override it. Get one free at klipy.com/developers — stored locally, never sent to teammates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Nudge sends an encrypted hand-wave through ntfy.sh on a topic derived from your team password. The whole team shares one topic and decodes the same payloads; recipients filter pings addressed to them. No backend, no accounts, no plaintext on the wire.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("How this works")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nudge")
        .sheet(isPresented: $showingPasswordSheet) {
            NudgePasswordPickerView {
                showingPasswordSheet = false
            }
        }
        .onChange(of: identity.current) { _, newValue in
            nameDraft = newValue ?? ""
        }
        .onAppear {
            connectorManager.refresh()
        }
    }

    private func agentConnectorRow(_ source: AgentSource) -> some View {
        let status = connectorManager.status(for: source)
        let mutation = connectorManager.mutation(for: source)
        let requiresManualRepair = connectorManager.requiresManualConnectorRepair(
            for: source
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: connectorIcon(for: source))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(connectorName(for: source))
                    .fontWeight(.medium)

                Spacer()

                connectorStatusView(status)

                if requiresManualRepair {
                    Text("Manuell prüfen")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button(connectorActionTitle(for: status, mutation: mutation)) {
                        performConnectorMutation(mutation, source: source)
                    }
                    .disabled(status == .installing)
                }

                Button("Demo anzeigen") {
                    _ = agentAttention.showDemo(source: source)
                }
                .disabled(agentAttention.state.activeRequest != nil)
            }

            if let help = connectorHelp(for: source, status: status) {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(status.isFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func connectorStatusView(_ status: AgentConnectorStatus) -> some View {
        switch status {
        case .notInstalled:
            Label("Nicht verbunden", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .installing:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text("Wird eingerichtet")
            }
            .foregroundStyle(.secondary)
        case .needsTrust:
            Label("Installiert", systemImage: "checkmark.circle")
                .foregroundStyle(.orange)
        case .connected:
            Label("Bereit", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("Fehler", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func connectorName(for source: AgentSource) -> String {
        source == .claudeCode ? "Claude Code" : "Codex"
    }

    private func connectorIcon(for source: AgentSource) -> String {
        source == .claudeCode ? "sparkles" : "terminal"
    }

    private func connectorActionTitle(
        for status: AgentConnectorStatus,
        mutation: AgentConnectorMutation
    ) -> String {
        switch status {
        case .connected, .needsTrust:
            return "Trennen"
        case .notInstalled:
            return "Verbinden"
        case .installing:
            return "Bitte warten"
        case .failed:
            return mutation == .disconnect
                ? "Trennung fortsetzen"
                : "Erneut verbinden"
        }
    }

    private func performConnectorMutation(
        _ mutation: AgentConnectorMutation,
        source: AgentSource
    ) {
        Task {
            switch mutation {
            case .connect:
                await connectorManager.connect(source)
            case .disconnect:
                await connectorManager.disconnect(source)
            }
        }
    }

    private func connectorHelp(
        for source: AgentSource,
        status: AgentConnectorStatus
    ) -> String? {
        if case let .failed(message) = status {
            return message
        }

        switch (source, status) {
        case (.claudeCode, .connected):
            return "Auf Benutzerebene bereit. In laufenden Sessions /reload-plugins ausführen; Workspace-Regeln können Plugins separat deaktivieren."
        case (.claudeCode, .notInstalled):
            return "Installiert das lokale Nudge-Plugin für deinen Benutzer."
        case (.codex, .notInstalled):
            return "Installiert einen lokalen Hook. Danach einmal mit /hooks prüfen und vertrauen."
        case (.codex, .needsTrust), (.codex, .connected):
            return "\(AgentConnectorManager.codexTrustInstruction). Nudge kann den finalen Trust-Status nicht auslesen."
        case (_, .installing):
            return "Die lokale Integration wird eingerichtet."
        default:
            return nil
        }
    }

    private func saveName() {
        let cleaned = NudgeIdentity.sanitize(nameDraft)
        guard NudgeIdentity.isValid(cleaned) else {
            nameError = "1–\(nudgeMaxNameLength) characters, no colons."
            return
        }
        nameError = nil
        identity.setCurrent(cleaned)
    }
}

private extension AgentConnectorStatus {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

#if DEBUG
#Preview {
    SettingsView()
}
#endif
