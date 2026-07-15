//
//  NudgeGifService.swift
//  Nudge
//
//  GIF search via KLIPY (https://klipy.com/developers). Tenor was shut down
//  by Google on 2026-06-30; KLIPY is the drop-in successor. The service is
//  provider-abstracted so swapping again later is a small change.
//
//  The team-wide API key is NOT in source (public repo). CI injects the
//  `KLIPY_API_KEY` GitHub Actions secret into the app's Info.plist at build
//  time (`KlipyAPIKey` = `$(KLIPY_API_KEY)`); a per-user key in Settings
//  overrides it. Local dev builds leave it empty and fall back to Settings.
//

import Foundation
import Defaults
import os

/// A single GIF search result.
struct NudgeGif: Identifiable, Equatable {
    let id: String
    /// Small looping preview used in the picker grid.
    let previewURL: URL
    /// URL actually sent to teammates (kept small — it renders in the notch).
    let sendURL: URL
    let description: String
}

enum NudgeGifError: LocalizedError {
    case noAPIKey
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Add a Klipy API key in Settings → GIFs."
        case .badResponse: return "Couldn't reach the GIF service."
        }
    }
}

@MainActor
enum NudgeGifService {
    private static let log = Logger(subsystem: "com.ontora.nudge", category: "gif")

    /// Team-wide default key from Info.plist (CI-injected). Empty in local dev.
    private static var bundledKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "KlipyAPIKey") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The user's own key if set, otherwise the shared bundled key.
    private static var effectiveKey: String {
        let user = Defaults[.klipyApiKey].trimmingCharacters(in: .whitespaces)
        return user.isEmpty ? bundledKey : user
    }

    static var isConfigured: Bool { !effectiveKey.isEmpty }

    /// Search GIFs for `query`. Empty query returns trending.
    static func search(_ query: String, limit: Int = 24) async throws -> [NudgeGif] {
        let key = effectiveKey
        guard !key.isEmpty else { throw NudgeGifError.noAPIKey }
        return try await KlipyProvider.search(query: query, key: key, limit: limit)
    }
}

// MARK: - KLIPY provider

private enum KlipyProvider {
    static func search(query: String, key: String, limit: Int) async throws -> [NudgeGif] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let trending = q.isEmpty
        var comps = URLComponents(
            string: "https://api.klipy.com/api/v1/\(key)/gifs/" + (trending ? "trending" : "search")
        )!
        var items = [
            URLQueryItem(name: "per_page", value: String(min(max(limit, 8), 50))),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "customer_id", value: "nudge"),
        ]
        if !trending { items.insert(URLQueryItem(name: "q", value: q), at: 0) }
        comps.queryItems = items

        do {
            let (data, resp) = try await URLSession.shared.data(from: comps.url!)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NudgeGifError.badResponse
            }
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            // { result, data: { data: [items], ... } }  — tolerate a flat array too.
            let container = root["data"]
            let list = (container as? [[String: Any]])
                ?? ((container as? [String: Any])?["data"] as? [[String: Any]])
                ?? []
            return list.compactMap(parse)
        } catch {
            // Trending is best-effort (endpoint/params may vary); don't surface
            // an error for the picker's initial load.
            if trending { return [] }
            throw error is NudgeGifError ? error : NudgeGifError.badResponse
        }
    }

    /// `file.<size>.<format>.url`, sizes xs/sm/md/hd, formats gif/webp/jpg/mp4/webm.
    private static func parse(_ item: [String: Any]) -> NudgeGif? {
        let file = item["file"] as? [String: Any] ?? [:]
        // sm is a good notch/grid size; fall back up/down and to a recursive scan.
        let preview = url(file, size: "sm", "gif") ?? url(file, size: "xs", "gif")
            ?? url(file, size: "md", "gif") ?? anyGifURL(file)
        let send = url(file, size: "sm", "gif") ?? url(file, size: "md", "gif")
            ?? url(file, size: "xs", "gif") ?? url(file, size: "hd", "gif") ?? anyGifURL(file)
        guard let previewStr = preview, let sendStr = send,
              let p = URL(string: previewStr), let s = URL(string: sendStr) else {
            return nil
        }
        let id = item["id"].map { "\($0)" } ?? sendStr
        let desc = (item["title"] as? String) ?? (item["slug"] as? String) ?? "GIF"
        return NudgeGif(id: id, previewURL: p, sendURL: s, description: desc)
    }

    private static func url(_ file: [String: Any], size: String, _ format: String) -> String? {
        ((file[size] as? [String: Any])?[format] as? [String: Any])?["url"] as? String
    }

    /// Last resort: first `.gif` URL found anywhere in the file tree.
    private static func anyGifURL(_ obj: Any) -> String? {
        if let s = obj as? String, s.hasPrefix("http"), s.contains(".gif") { return s }
        if let dict = obj as? [String: Any] {
            for v in dict.values { if let f = anyGifURL(v) { return f } }
        }
        if let arr = obj as? [Any] {
            for v in arr { if let f = anyGifURL(v) { return f } }
        }
        return nil
    }
}
