//
//  NudgeStats.swift
//  Nudge
//
//  Tracks per-week nudge counters: how many you've sent (per peer + total)
//  and received (per peer). Also keeps a peer-leaderboard table of what
//  each teammate has self-reported via their own pings, so we can show a
//  cross-team weekly leaderboard with no backend.
//

import Foundation
import Combine

@MainActor
final class NudgeStats: ObservableObject {
    static let shared = NudgeStats()

    /// Bumped on every write so SwiftUI views observing this object refresh.
    @Published private(set) var lastUpdate: Date = .distantPast

    private let countsKey = "nudgeCounts"        // "sent:<peer>:<week>" / "recv:<peer>:<week>" -> Int
    private let peerLBKey = "nudgePeerLeaderboard" // "<peer>:<week>" -> peer's self-reported weekSends

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

    // MARK: - Week bucketing

    /// ISO year-week, e.g. "2026-W20". Resets every Monday.
    var currentWeek: String {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let now = Date()
        let yfw = cal.component(.yearForWeekOfYear, from: now)
        let woy = cal.component(.weekOfYear, from: now)
        return String(format: "%04d-W%02d", yfw, woy)
    }

    // MARK: - Writes

    func recordSent(to peer: String) {
        let key = "sent:\(peer):\(currentWeek)"
        counts[key, default: 0] += 1
        persist()
    }

    func recordReceived(from peer: String) {
        let key = "recv:\(peer):\(currentWeek)"
        counts[key, default: 0] += 1
        persist()
    }

    /// Record what a peer claims their own week-sends total is.
    /// Monotonic — never accept a lower number (clock skew / stale messages).
    func recordPeerLeaderboard(peer: String, weekSends: Int) {
        guard weekSends > 0 else { return }
        let key = "\(peer):\(currentWeek)"
        let existing = peerLB[key] ?? 0
        if weekSends > existing {
            peerLB[key] = weekSends
            persist()
        }
    }

    // MARK: - Reads

    var mySendsThisWeek: Int {
        let suffix = ":\(currentWeek)"
        return counts
            .filter { $0.key.hasPrefix("sent:") && $0.key.hasSuffix(suffix) }
            .map(\.value)
            .reduce(0, +)
    }

    func sentThisWeek(to peer: String) -> Int {
        counts["sent:\(peer):\(currentWeek)"] ?? 0
    }

    func receivedThisWeek(from peer: String) -> Int {
        counts["recv:\(peer):\(currentWeek)"] ?? 0
    }

    func sentBreakdownThisWeek() -> [(peer: String, count: Int)] {
        nudgeUsers.compactMap { peer in
            let n = sentThisWeek(to: peer)
            return n > 0 ? (peer, n) : nil
        }
    }

    func receivedBreakdownThisWeek() -> [(peer: String, count: Int)] {
        nudgeUsers.compactMap { peer in
            let n = receivedThisWeek(from: peer)
            return n > 0 ? (peer, n) : nil
        }
    }

    func leaderboardThisWeek() -> [(peer: String, sends: Int)] {
        let week = currentWeek
        let me = NudgeIdentity.shared.current
        return nudgeUsers.map { user -> (String, Int) in
            if user == me {
                return (user, mySendsThisWeek)
            } else {
                return (user, peerLB["\(user):\(week)"] ?? 0)
            }
        }
        .sorted { $0.1 > $1.1 }
        .map { (peer: $0.0, sends: $0.1) }
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(counts, forKey: countsKey)
        UserDefaults.standard.set(peerLB, forKey: peerLBKey)
        lastUpdate = Date()
    }
}
