//
//  NudgeStats.swift
//  Nudge
//
//  Tracks GLOBAL (all-time) nudge counters: how many you've sent (per peer
//  + total) and received (per peer + total). Never resets. Also keeps a
//  peer-leaderboard table of what each teammate has self-reported via their
//  own pings, so we can show a cross-team leaderboard with no backend.
//

import Foundation
import Combine

@MainActor
final class NudgeStats: ObservableObject {
    static let shared = NudgeStats()

    /// Bumped on every write so SwiftUI views observing this object refresh.
    @Published private(set) var lastUpdate: Date = .distantPast

    private let countsKey = "nudgeCountsAllTime"       // "sent:<peer>" / "recv:<peer>" -> Int
    private let peerLBKey = "nudgePeerLeaderboardAllTime" // "<peer>" -> peer's self-reported total sends

    private var counts: [String: Int] = [:]
    private var peerLB: [String: Int] = [:]

    private init() {
        if let dict = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] {
            counts = dict
        }
        if let dict = UserDefaults.standard.dictionary(forKey: peerLBKey) as? [String: Int] {
            peerLB = dict
        }
    }

    // MARK: - Writes

    func recordSent(to peer: String) {
        counts["sent:\(peer)", default: 0] += 1
        persist()
    }

    func recordReceived(from peer: String) {
        counts["recv:\(peer)", default: 0] += 1
        persist()
    }

    /// Record what a peer claims their own all-time send total is.
    /// Monotonic — never accept a lower number (clock skew / stale messages).
    func recordPeerLeaderboard(peer: String, totalSends: Int) {
        guard totalSends > 0 else { return }
        let existing = peerLB[peer] ?? 0
        if totalSends > existing {
            peerLB[peer] = totalSends
            persist()
        }
    }

    // MARK: - Reads

    var mySendsTotal: Int {
        counts.filter { $0.key.hasPrefix("sent:") }.map(\.value).reduce(0, +)
    }

    var myReceivedTotal: Int {
        counts.filter { $0.key.hasPrefix("recv:") }.map(\.value).reduce(0, +)
    }

    func sentTotal(to peer: String) -> Int {
        counts["sent:\(peer)"] ?? 0
    }

    func receivedTotal(from peer: String) -> Int {
        counts["recv:\(peer)"] ?? 0
    }

    func sentBreakdown() -> [(peer: String, count: Int)] {
        counts
            .filter { $0.key.hasPrefix("sent:") && $0.value > 0 }
            .map { (peer: String($0.key.dropFirst("sent:".count)), count: $0.value) }
            .sorted { $0.peer.localizedCaseInsensitiveCompare($1.peer) == .orderedAscending }
    }

    func receivedBreakdown() -> [(peer: String, count: Int)] {
        counts
            .filter { $0.key.hasPrefix("recv:") && $0.value > 0 }
            .map { (peer: String($0.key.dropFirst("recv:".count)), count: $0.value) }
            .sorted { $0.peer.localizedCaseInsensitiveCompare($1.peer) == .orderedAscending }
    }

    func leaderboard() -> [(peer: String, sends: Int)] {
        let me = NudgeIdentity.shared.current
        let names = NudgeRoster.shared.everyone(including: me)
        return names.map { name -> (peer: String, sends: Int) in
            if name == me {
                return (peer: name, sends: mySendsTotal)
            } else {
                return (peer: name, sends: peerLB[name] ?? 0)
            }
        }
        .sorted { $0.sends > $1.sends }
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(counts, forKey: countsKey)
        UserDefaults.standard.set(peerLB, forKey: peerLBKey)
        lastUpdate = Date()
    }
}
