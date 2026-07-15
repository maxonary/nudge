//
//  NudgeIdentity.swift
//  Nudge
//

import Foundation
import Combine

@MainActor
final class NudgeIdentity: ObservableObject {
    static let shared = NudgeIdentity()

    @Published private(set) var current: String?

    private let storageKey = "nudgeCurrentUser"

    private init() {
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           NudgeIdentity.isValid(stored) {
            self.current = stored
        } else {
            self.current = nil
        }
    }

    static func isValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= nudgeMaxNameLength else { return false }
        // ':' is our key separator in stats/roster storage. Disallow it
        // to keep persistence keys unambiguous.
        guard !trimmed.contains(":") else { return false }
        return true
    }

    static func sanitize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setCurrent(_ user: String) {
        let cleaned = NudgeIdentity.sanitize(user)
        guard NudgeIdentity.isValid(cleaned) else { return }
        UserDefaults.standard.set(cleaned, forKey: storageKey)
        self.current = cleaned
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        self.current = nil
    }
}
