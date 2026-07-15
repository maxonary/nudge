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
    @EnvironmentObject var vm: NudgeViewModel

    @State private var sending: String?
    @State private var sendError: String?
    @State private var messageText: String = ""
    @FocusState private var messageFocused: Bool

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
        Group {
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
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        messageField
                        gifButton
                    }
                    HStack(spacing: 10) {
                        ForEach(others, id: \.self) { other in
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

    private var gifButton: some View {
        Button {
            GifPickerWindowController.shared.showWindow()
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Send a GIF")
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
        VStack(spacing: 6) {
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
            }
            if let gif = ping.gif, let url = URL(string: gif) {
                AnimatedGifView(url: url)
                    .frame(maxWidth: 200, maxHeight: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
