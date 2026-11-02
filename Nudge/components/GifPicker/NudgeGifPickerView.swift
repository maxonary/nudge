//
//  NudgeGifPickerView.swift
//  Nudge
//
//  Search KLIPY and attach a GIF to the notch draft before sending.
//  Embedded below the composer while the notch expands for browsing.
//

import SwiftUI

struct NudgeGifPickerView: View {
    @ObservedObject var identity = NudgeIdentity.shared
    @ObservedObject var teamSecret = NudgeTeamSecret.shared

    @State private var query: String = ""
    @State private var results: [NudgeGif] = []
    @State private var loading: Bool = false
    @State private var error: String?

    let onClose: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

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
                searchRow
                resultsGrid
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: query) { await runSearch(query) }
    }

    private var header: some View {
        HStack {
            Label("Choose a GIF", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
            Spacer()
            Button("Close", action: onClose)
                .help("Close GIF picker")
        }
    }

    private var notConfigured: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No Klipy API key yet")
                .font(.headline)
            Text("Paste a Klipy API key in Settings → GIFs to search and send GIFs.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                SettingsWindowController.shared.showWindow()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchRow: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search GIFs", text: $query)
                .textFieldStyle(.plain)
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
                        NudgeDraft.shared.attach(gif)
                    } label: {
                        AnimatedGifView(url: gif.previewURL)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 90)
                            .clipped()
                            .background(Color.black.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose GIF: \(gif.description)")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    private func runSearch(_ searchQuery: String) async {
        guard NudgeGifService.isConfigured, identity.current != nil, teamSecret.hasPassword else { return }
        error = nil
        loading = true
        defer {
            // An older cancelled search must not clear the newer search's spinner.
            if !Task.isCancelled { loading = false }
        }
        do {
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await Task.sleep(for: .milliseconds(250))
            }
            try Task.checkCancellation()
            let matches = try await NudgeGifService.search(searchQuery)
            // Ignore stale responses when the user has already typed another query.
            try Task.checkCancellation()
            results = matches
        } catch {
            guard !Task.isCancelled else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? "Search failed"
        }
    }
}
