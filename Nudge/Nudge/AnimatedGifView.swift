//
//  AnimatedGifView.swift
//  Nudge
//
//  Renders an animated GIF from a remote URL. AppKit's NSImageView plays
//  multi-frame GIFs natively, so no third-party dependency is needed. The
//  fetched data is cached in-process so re-renders don't re-download.
//

import SwiftUI
import AppKit

/// Lightweight in-process cache of downloaded GIF data, keyed by URL.
@MainActor
private final class GifDataCache {
    static let shared = GifDataCache()
    private var store: [URL: Data] = [:]
    private let maxEntries = 40

    func data(for url: URL) -> Data? { store[url] }

    func insert(_ data: Data, for url: URL) {
        if store.count >= maxEntries, let first = store.keys.first {
            store.removeValue(forKey: first)
        }
        store[url] = data
    }
}

struct AnimatedGifView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.loadedURL = url
        load(into: view, coordinator: context.coordinator)
        return view
    }

    // Respect SwiftUI's cell size instead of the downloaded image's intrinsic size.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 110, height: 90))
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // Only reload if the URL changed (avoid restarting playback each pass).
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            load(into: nsView, coordinator: context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var loadedURL: URL?
        var loadTask: Task<Void, Never>?
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        coordinator.loadTask = nil
        nsView.animates = false
        nsView.image = nil
    }

    private func load(into view: NSImageView, coordinator: Coordinator) {
        coordinator.loadTask?.cancel()
        view.image = nil
        if let cached = GifDataCache.shared.data(for: url) {
            view.image = NSImage(data: cached)
            return
        }
        let url = self.url
        coordinator.loadTask = Task { @MainActor [weak view, weak coordinator] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  coordinator?.loadedURL == url,
                  let view,
                  let image = NSImage(data: data) else { return }
            GifDataCache.shared.insert(data, for: url)
            view.image = image
        }
    }
}
