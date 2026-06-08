//
//  NudgeNotchView.swift
//  Nudge
//

import SwiftUI
import AppKit

struct NudgeNotchView: View {
    @ObservedObject var transport: NudgeTransport = .shared
    @ObservedObject var identity: NudgeIdentity = .shared
    @EnvironmentObject var vm: NudgeViewModel

    @State private var sending: String?
    @State private var sendError: String?
    @State private var messageText: String = ""
    @FocusState private var messageFocused: Bool

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
        Group {
            if identity.current == nil {
                Text("Pick a name in Settings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if identity.others.isEmpty {
                Text("No teammates configured")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    messageField
                    HStack(spacing: 10) {
                        ForEach(identity.others, id: \.self) { other in
                            pingButton(other)
                        }
                        if let err = sendError {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private var messageField: some View {
        TextField("Add a message (optional)", text: $messageText)
            .textFieldStyle(.plain)
            .focused($messageFocused)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
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
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: 36, height: 36)
                Text(String(ping.sender.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ping.sender) wants you")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                if let message = ping.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                Text(ping.receivedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func tap(_ recipient: String) {
        guard let me = identity.current else { return }
        sending = recipient
        sendError = nil
        messageFocused = false
        let outgoing = messageText
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        Task {
            do {
                try await transport.send(to: recipient, from: me, message: outgoing)
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    self.sending = nil
                    self.messageText = ""
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
