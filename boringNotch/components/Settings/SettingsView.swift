//
//  SettingsView.swift
//  Nudge
//

import AppKit
import Defaults
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            NudgeSettingsPane()
        }
        .frame(width: 540, height: 520)
    }
}

struct NudgeSettingsPane: View {
    @ObservedObject var identity = NudgeIdentity.shared
    @ObservedObject var teamSecret = NudgeTeamSecret.shared
    @ObservedObject var stats = NudgeStats.shared
    @Default(.nudgePlaySoundOnReceive) var playSoundOnReceive
    @Default(.nudgeShowBackupNotification) var showBackupNotification
    @State private var showingPasswordSheet: Bool = false

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
                Text("Everyone on your team must type the same password. It encrypts your pings end-to-end and decides who can reach you. Stored in Keychain, never sent over the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                let lb = stats.leaderboardThisWeek()
                let allZero = lb.allSatisfy { $0.sends == 0 }
                if allZero {
                    Text("No nudges yet this week.")
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

                let sent = stats.sentBreakdownThisWeek()
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

                let recv = stats.receivedBreakdownThisWeek()
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
                Text("This week (\(stats.currentWeek))")
            } footer: {
                Text("Each row is what that teammate has reported via their pings this week. Someone who hasn't pinged yet shows 0.")
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
                Text("Nudge sends an encrypted hand-wave through ntfy.sh under a topic derived from your team password. No backend, no accounts, no plaintext on the wire. When someone pings you, your notch expands for ~6 seconds; a macOS notification fires as a backup in case the notch is off-screen.")
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
    }
}

#Preview {
    SettingsView()
}
