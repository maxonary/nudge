//
//  NudgeGifService.swift
//  Nudge
//
//  GIF search. Provider-abstracted so swapping Tenor <-> Giphy is a small
//  change; Tenor is the default. The API key is stored in Defaults
//  (`tenorApiKey`) and pasted by the user in Settings — nothing embedded.
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
        case .noAPIKey: return "Add a Tenor API key in Settings → GIFs."
        case .badResponse: return "Couldn't reach the GIF service."
        }
    }
}

@MainActor
enum NudgeGifService {
    private static let log = Logger(subsystem: "com.ontora.nudge", category: "gif")

    static var isConfigured: Bool {
        !Defaults[.tenorApiKey].trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Search GIFs for `query`. Empty query returns featured/trending.
    static func search(_ query: String, limit: Int = 24) async throws -> [NudgeGif] {
        let key = Defaults[.tenorApiKey].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw NudgeGifError.noAPIKey }
        return try await TenorProvider.search(query: query, key: key, limit: limit)
    }
}

// MARK: - Tenor (Google) provider

private enum TenorProvider {
    static func search(query: String, key: String, limit: Int) async throws -> [NudgeGif] {
        var comps = URLComponents(string:
            query.trimmingCharacters(in: .whitespaces).isEmpty
                ? "https://tenor.googleapis.com/v2/featured"
                : "https://tenor.googleapis.com/v2/search")!
        var items = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "client_key", value: "nudge"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "media_filter", value: "tinygif,nanogif,gif"),
            URLQueryItem(name: "contentfilter", value: "high"),
        ]
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { items.insert(URLQueryItem(name: "q", value: q), at: 0) }
        comps.queryItems = items

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NudgeGifError.badResponse
        }
        let decoded = try JSONDecoder().decode(TenorResponse.self, from: data)
        return decoded.results.compactMap { $0.asNudgeGif }
    }

    // Minimal shapes for the fields we use.
    private struct TenorResponse: Decodable { let results: [Result] }

    private struct Result: Decodable {
        let id: String
        let content_description: String?
        let media_formats: [String: Format]

        var asNudgeGif: NudgeGif? {
            // Preview: prefer the tiniest looping format.
            let previewStr = media_formats["nanogif"]?.url
                ?? media_formats["tinygif"]?.url
                ?? media_formats["gif"]?.url
            // Send: tinygif keeps the notch payload light.
            let sendStr = media_formats["tinygif"]?.url
                ?? media_formats["nanogif"]?.url
                ?? media_formats["gif"]?.url
            guard let previewStr, let sendStr,
                  let preview = URL(string: previewStr), let send = URL(string: sendStr) else {
                return nil
            }
            return NudgeGif(
                id: id,
                previewURL: preview,
                sendURL: send,
                description: content_description ?? "GIF"
            )
        }
    }

    private struct Format: Decodable { let url: String }
}
