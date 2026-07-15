//
//  NudgeGifPickerView.swift
//  Nudge
//
//  Search KLIPY, pick a GIF, choose a teammate, optionally add a message,
//  and send. Lives in its own panel (see GifPickerWindowController) so the
//  ephemeral notch doesn't dismiss it mid-search.
//

import SwiftUI

struct NudgeGifPickerView: View {
    @ObservedObject var identity = NudgeIdentity.shared
    @ObservedObject var roster = NudgeRoster.shared
    @ObservedObject var teamSecret = NudgeTeamSecret.shared

    @State private var query: String = ""
    @State private var results: [NudgeGif] = []
    @State private var selected: NudgeGif?
    @State private var message: String = ""
    @State private var recipient: String = ""
    @State private var loading: Bool = false
    @State private var error: String?
    @State private var sending: Bool = false

    let onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    private var others: [String] { roster.others(excluding: identity.current) }

    var body: some View {
        VStack(spacing: 12) {
            header

            if !NudgeGifService.isConfigured {
                notConfigured
            } else if identity.current == nil || !teamSecret.hasPassword {
                Text("Finish onboarding (name + team password) before sending GIFs.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                recipientRow
                searchRow
                resultsGrid
                composeRow
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 520)
        .task { await initialLoad() }
        .onAppear { if recipient.isEmpty { recipient = others.first ?? "" } }
    }

    private var header: some View {
        HStack {
            Label("Send a GIF", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
            Spacer()
            Button("Close", action: onClose)
        }
    }

    private var notConfigured: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Klipy API key yet")
                .font(.title3.weight(.semibold))
            Text("Paste a Klipy API key in Settings → GIFs to search and send GIFs.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                SettingsWindowController.shared.showWindow()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recipientRow: some View {
        HStack {
            Text("To")
            if others.isEmpty {
                Text("No teammates online yet")
                    .foregroundStyle(.secondary)
            } else {
                Picker("", selection: $recipient) {
                    ForEach(others, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            Spacer()
        }
    }

    private var searchRow: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search GIFs", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { Task { await runSearch() } }
            if loading { ProgressView().controlSize(.small) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(results) { gif in
                    Button {
                        selected = gif
                    } label: {
                        AnimatedGifView(url: gif.previewURL)
                            .frame(height: 90)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selected == gif ? Color.accentColor : .clear, lineWidth: 3)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var composeRow: some View {
        VStack(spacing: 8) {
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                TextField("Add a message (optional)", text: $message)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await send() }
                } label: {
                    if sending { ProgressView().controlSize(.small) }
                    else { Label("Send", systemImage: "paperplane.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || recipient.isEmpty || sending)
            }
        }
    }

    // MARK: - Actions

    private func initialLoad() async {
        guard NudgeGifService.isConfigured, results.isEmpty else { return }
        await runSearch()
    }

    private func runSearch() async {
        error = nil
        loading = true
        defer { loading = false }
        do {
            results = try await NudgeGifService.search(query)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Search failed"
        }
    }

    private func send() async {
        guard let me = identity.current, let gif = selected, !recipient.isEmpty else { return }
        sending = true
        error = nil
        do {
            try await NudgeTransport.shared.send(
                to: recipient, from: me, message: message, gif: gif.sendURL.absoluteString
            )
            onClose()
        } catch {
            self.error = "Send failed"
        }
        sending = false
    }
}
