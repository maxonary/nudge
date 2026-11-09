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
    @ObservedObject var draft = NudgeDraft.shared
    @ObservedObject var roster: NudgeRoster = .shared
    @ObservedObject var agentAttention: AgentAttentionCenter = .shared
    @ObservedObject var activityLog: ActivityLogStore = .shared
    @EnvironmentObject var vm: NudgeViewModel

    let agentFocusController: AgentPanelFocusController

    @State private var sending: String?
    @State private var sendError: String?
    @FocusState private var messageFocused: Bool

    init(agentFocusController: AgentPanelFocusController = AgentPanelFocusController()) {
        self.agentFocusController = agentFocusController
    }

    private var others: [String] {
        roster.others(excluding: identity.current)
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if agentAttention.hasVisibleAgentContent {
                    AgentAttentionView(
                        center: agentAttention,
                        focusController: agentFocusController
                    )
                    .onPreferenceChange(AgentContentHeightPreference.self) { height in
                        vm.updateAgentContentHeight(height)
                    }
                } else if let ping = transport.lastIncoming, isRecent(ping), !draft.isShowingSentConfirmation, !draft.isAwaitingReceipt, !draft.isPickingGIF {
                    incomingView(for: ping)
                } else {
                    sendView
                }
            }
            if !agentAttention.hasVisibleAgentContent, !draft.isPickingGIF, !activityLog.entries.isEmpty {
                ActivityLogView(store: activityLog, center: agentAttention)
                    .transition(.opacity)
            }
            if draft.isPickingGIF {
                NudgeGifPickerView {
                    draft.isPickingGIF = false
                }
                .frame(height: gifPickerExtraHeight - 8)
                .transition(.move(edge: .top).combined(with: .opacity))
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
                    Grid(verticalSpacing: 8) {
                        if let gif = draft.gif {
                            GridRow {
                                AnimatedGifView(url: gif.sendURL)
                                    .frame(height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            draft.gif = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .black.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(4)
                                        .help("Remove GIF")
                                        .accessibilityLabel("Remove GIF")
                                    }
                                    .accessibilityLabel("GIF preview: \(gif.description)")
                                    .gridCellUnsizedAxes(.horizontal)
                            }
                        }
                        GridRow {
                            HStack(spacing: 8) {
                                messageField
                                gifButton
                            }
                            .gridCellUnsizedAxes(.horizontal)
                        }
                        GridRow {
                            HStack(spacing: 10) {
                                ForEach(others, id: \.self) { other in
                                    pingButton(other)
                                }
                            }
                        }
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

    private var messageField: some View {
        ZStack {
            TextField("Add a message (optional)", text: $draft.message)
                .textFieldStyle(.plain)
                .focused($messageFocused)
                .onTapGesture { messageFocused = true }
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
                .opacity(draft.isShowingSentConfirmation || draft.isAwaitingReceipt ? 0 : 1)
                .disabled(draft.isShowingSentConfirmation || draft.isAwaitingReceipt)
                .accessibilityHidden(draft.isShowingSentConfirmation || draft.isAwaitingReceipt)

            if draft.isAwaitingReceipt {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Waiting for receipt")
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: draft.isShowingSentConfirmation)
                .opacity(draft.isShowingSentConfirmation ? 1 : 0)
                .accessibilityLabel("Nudge received")
                .accessibilityHidden(!draft.isShowingSentConfirmation)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }

    private var gifButton: some View {
        Button {
            draft.openGIFPicker()
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
        .help("Choose a GIF")
        .disabled(sending != nil || draft.isPickingGIF)
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
        .disabled(sending != nil || draft.isAwaitingReceipt || draft.isShowingSentConfirmation)
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
        guard let me = identity.current,
              !draft.isAwaitingReceipt, !draft.isShowingSentConfirmation else { return }
        draft.isPickingGIF = false
        sending = recipient
        sendError = nil
        messageFocused = false
        let outgoing = draft.message
        let outgoingGif = draft.gif
        let hasText = !outgoing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        draft.isAwaitingReceipt = hasText
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        Task {
            do {
                let received = try await transport.send(to: recipient, from: me, message: outgoing, gif: outgoingGif?.sendURL.absoluteString, confirmDelivery: hasText)
                let showConfirmation = hasText && received && self.vm.notchState == .open
                if showConfirmation {
                    await MainActor.run {
                        self.draft.isShowingSentConfirmation = true
                        self.draft.isAwaitingReceipt = false
                        self.vm.open()
                    }
                }
                if hasText && !received {
                    await MainActor.run {
                        self.draft.isAwaitingReceipt = false
                        self.sending = nil
                        self.sendError = "Sent — receipt not confirmed"
                        if self.draft.message == outgoing { self.draft.message = "" }
                        if self.draft.gif == outgoingGif { self.draft.gif = nil }
                    }
                    return
                }
                self.draft.isAwaitingReceipt = false
                try? await Task.sleep(for: .milliseconds(showConfirmation ? 1400 : 400))
                await MainActor.run {
                    self.draft.isShowingSentConfirmation = false
                    self.sending = nil
                    if self.draft.message == outgoing { self.draft.message = "" }
                    if self.draft.gif == outgoingGif { self.draft.gif = nil }
                    self.vm.close()
                }
            } catch {
                await MainActor.run {
                    self.sending = nil
                    self.draft.isAwaitingReceipt = false
                    self.sendError = "Send failed"
                }
            }
        }
    }

    private func isRecent(_ ping: NudgePing) -> Bool {
        Date().timeIntervalSince(ping.receivedAt) < 6
    }
}
