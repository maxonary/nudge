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
        let stored = UserDefaults.standard.string(forKey: storageKey)
        if let stored, nudgeUsers.contains(stored) {
            self.current = stored
        } else {
            self.current = nil
        }
    }

    func setCurrent(_ user: String) {
        guard nudgeUsers.contains(user) else { return }
        UserDefaults.standard.set(user, forKey: storageKey)
        self.current = user
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        self.current = nil
    }

    var others: [String] {
        guard let me = current else { return nudgeUsers }
        return nudgeUsers.filter { $0 != me }
    }
}
