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
        .frame(width: 540, height: 480)
    }
}

struct NudgeSettingsPane: View {
    @ObservedObject var identity = NudgeIdentity.shared
    @Default(.nudgePlaySoundOnReceive) var playSoundOnReceive
    @Default(.nudgeShowBackupNotification) var showBackupNotification
    @State private var copiedNonce: Bool = false
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
                    Text("Current user")
                    Spacer()
                    Text(identity.current ?? "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    ForEach(nudgeUsers, id: \.self) { user in
                        Button {
                            identity.setCurrent(user)
                        } label: {
                            Text(user)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(identity.current == user ? .accentColor : .secondary)
                    }
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("Pick who you are. Every Ontora teammate's build runs this app.")
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
                HStack {
                    Text("Topic nonce")
                        .frame(width: 120, alignment: .leading)
                    Text(nudgeNonce)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button(copiedNonce ? "Copied!" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(nudgeNonce, forType: .string)
                        copiedNonce = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await MainActor.run { copiedNonce = false }
                        }
                    }
                }
            } header: {
                Text("Shared nonce")
            } footer: {
                Text("All Ontora teammates' builds must have the exact same nonce. Rotate by editing NudgeConstants.swift and shipping a new build to everyone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Nudge sends a hand-raise ping through ntfy.sh under a topic derived from the recipient's name + the shared nonce. No backend, no accounts — just \"X wants you\" plus an optional short message. When someone pings you, your notch expands for ~6 seconds; a macOS notification fires as a backup in case the notch is off-screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("How this works")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Nudge")
    }
}

#Preview {
    SettingsView()
}
