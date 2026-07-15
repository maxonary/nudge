//
//  NudgeRoster.swift
//  Nudge
//
//  Tracks which teammates have been seen on the shared team topic.
//  Populated by "hello" broadcasts from NudgeTransport on app launch and
//  on a periodic heartbeat; persisted in UserDefaults so a quick app
//  restart doesn't blank the ping buttons.
//

import Foundation
import Combine

@MainActor
final class NudgeRoster: ObservableObject {
    static let shared = NudgeRoster()

    /// name -> ISO8601 last-seen timestamp string.
    @Published private(set) var teammates: [String: Date] = [:]

    private let storageKey = "nudgeRoster"

    private init() {
        if let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: TimeInterval] {
            for (name, ts) in raw {
                teammates[name] = Date(timeIntervalSince1970: ts)
            }
        }
    }

    /// Record that we heard from `name` just now.
    func record(name rawName: String) {
        let name = NudgeIdentity.sanitize(rawName)
        guard NudgeIdentity.isValid(name) else { return }
        teammates[name] = Date()
        persist()
    }

    /// Forget everyone — used when the team password changes.
    func clear() {
        teammates.removeAll()
        persist()
    }

    /// All known teammates except `excluded` (the current identity), sorted
    /// alphabetically.
    func others(excluding excluded: String?) -> [String] {
        teammates.keys
            .filter { $0 != excluded }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Names known including yourself, sorted alphabetically.
    func everyone(including me: String?) -> [String] {
        var s = Set(teammates.keys)
        if let me { s.insert(me) }
        return s.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func persist() {
        let raw = Dictionary(
            uniqueKeysWithValues: teammates.map { ($0.key, $0.value.timeIntervalSince1970) }
        )
        UserDefaults.standard.set(raw, forKey: storageKey)
    }
}
