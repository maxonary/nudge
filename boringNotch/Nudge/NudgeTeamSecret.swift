//
//  NudgeTeamSecret.swift
//  Nudge
//
//  Holds the team password (in Keychain) and derives both the ntfy topic
//  nonce and the AES-GCM encryption key from it via HKDF-SHA256.
//  Everyone on the team types the same password; they land on the same
//  topic and can decrypt each other's messages. Anyone else who happens
//  to know the topic just sees ciphertext.
//

import Foundation
import Combine
import CryptoKit
import Security
import os

@MainActor
final class NudgeTeamSecret: ObservableObject {
    static let shared = NudgeTeamSecret()

    @Published private(set) var hasPassword: Bool = false

    private let log = Logger(subsystem: "com.ontora.nudge", category: "team-secret")
    private let service = "com.ontora.nudge.team-secret"
    private let account = "team"

    private var cachedKey: SymmetricKey?
    private var cachedNonce: String?

    private init() {
        if let pw = readPassword() {
            derive(from: pw)
            hasPassword = true
        }
    }

    // MARK: - Mutation

    func setPassword(_ pw: String) {
        let trimmed = pw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let previous = readPassword()
        writePassword(trimmed)
        derive(from: trimmed)
        hasPassword = true
        log.info("team password set")
        if previous != trimmed {
            // Joined (or rejoined under a new password) a different team —
            // the old roster came from a different topic and is stale.
            NudgeRoster.shared.clear()
            // Force resubscription on the new topic.
            if let me = NudgeIdentity.shared.current {
                NudgeTransport.shared.stopReceiving()
                NudgeTransport.shared.startReceiving(as: me)
            }
        }
    }

    func clearPassword() {
        deletePassword()
        cachedKey = nil
        cachedNonce = nil
        hasPassword = false
        log.info("team password cleared")
    }

    /// For the "show" toggle in Settings.
    func currentPassword() -> String? {
        readPassword()
    }

    // MARK: - Derived values

    /// `nudge-team-<12 hex chars derived from password>`. One topic for
    /// the whole team — recipient name moves into the encrypted payload.
    /// Returns nil if no password set.
    var teamTopic: String? {
        guard let nonce = cachedNonce else { return nil }
        return "nudge-team-\(nonce)"
    }

    func encrypt(_ plaintext: String) -> String? {
        guard let key = cachedKey,
              let data = plaintext.data(using: .utf8),
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else { return nil }
        return combined.base64EncodedString()
    }

    func decrypt(_ ciphertextB64: String) -> String? {
        let trimmed = ciphertextB64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = cachedKey,
              let data = Data(base64Encoded: trimmed),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key),
              let str = String(data: opened, encoding: .utf8) else { return nil }
        return str
    }

    // MARK: - Derivation

    private func derive(from password: String) {
        // HKDF-SHA256 derives two separate values from one password via
        // distinct `info` tags. Salt is a fixed app-level domain separator
        // (per-user salt isn't possible since everyone must derive the same
        // values to interoperate). For a 3-person internal tool with a
        // verbally-shared password this is adequate; a brute-force attacker
        // would have to guess the password to compute the topic.
        let ikm = SymmetricKey(data: Data(password.utf8))
        let salt = Data("nudge-ontora-v1".utf8)

        cachedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("nudge-encryption-key-v1".utf8),
            outputByteCount: 32
        )

        let nonceBytes = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikm,
            salt: salt,
            info: Data("nudge-topic-id-v1".utf8),
            outputByteCount: 6
        )
        cachedNonce = nonceBytes.withUnsafeBytes { buf in
            buf.map { String(format: "%02x", $0) }.joined()
        }
    }

    // MARK: - Keychain

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func readPassword() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private func writePassword(_ pw: String) {
        deletePassword()
        var q = baseQuery()
        q[kSecValueData as String] = Data(pw.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("keychain write failed: \(status)")
        }
    }

    private func deletePassword() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
