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
        context.coordinator.loadedURL = url
        load(into: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // Only reload if the URL changed (avoid restarting playback each pass).
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            load(into: nsView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
    }

    private func load(into view: NSImageView) {
        if let cached = GifDataCache.shared.data(for: url) {
            view.image = NSImage(data: cached)
            return
        }
        let url = self.url
        Task { @MainActor in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            GifDataCache.shared.insert(data, for: url)
            view.image = image
        }
    }
}
