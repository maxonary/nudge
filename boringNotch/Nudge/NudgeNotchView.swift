//
//  NudgeNotchView.swift
//  Nudge
//

import SwiftUI
import AppKit

struct NudgeNotchView: View {
    @ObservedObject var transport: NudgeTransport = .shared
    @ObservedObject var identity: NudgeIdentity = .shared
    @ObservedObject var teamSecret: NudgeTeamSecret = .shared
    @ObservedObject var roster: NudgeRoster = .shared
    @EnvironmentObject var vm: BoringViewModel

    @State private var sending: String?
    @State private var sendError: String?

    private var others: [String] {
        roster.others(excluding: identity.current)
    }

    var body: some View {
        Group {
            if let ping = transport.lastIncoming, isRecent(ping) {
                incomingView(for: ping)
            } else {
                sendView
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sendView: some View {
        HStack(spacing: 10) {
            if identity.current == nil {
                Text("Pick a name in Settings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !teamSecret.hasPassword {
                Text("Set team password in Settings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if others.isEmpty {
                Text("Waiting for teammates…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(others, id: \.self) { other in
                    pingButton(other)
                }
            }
            if let err = sendError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func pingButton(_ recipient: String) -> some View {
        let isSending = sending == recipient
        return Button {
            tap(recipient)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hand.wave.fill")
                Text("Ping \(recipient)")
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSending ? Color.green.opacity(0.6) : Color.white.opacity(0.12))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }

    private func incomingView(for ping: NudgePing) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: 26, height: 26)
                Text(String(ping.sender.prefix(1)))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .center, spacing: 2) {
                Text("\(ping.sender) is waving")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(ping.receivedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissIncoming()
        }
    }

    private func dismissIncoming() {
        transport.lastIncoming = nil
        vm.close()
    }

    private func tap(_ recipient: String) {
        guard let me = identity.current else { return }
        sending = recipient
        sendError = nil
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        Task {
            do {
                try await transport.send(to: recipient, from: me)
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    self.sending = nil
                    self.vm.close()
                }
            } catch {
                await MainActor.run {
                    self.sending = nil
                    self.sendError = "Send failed"
                }
            }
        }
    }

    private func isRecent(_ ping: NudgePing) -> Bool {
        Date().timeIntervalSince(ping.receivedAt) < 6
    }
}
