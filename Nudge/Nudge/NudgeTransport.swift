//
//  NudgeTransport.swift
//  Nudge
//
//  Single shared ntfy topic for the whole team (derived from password).
//  Every member subscribes; every message is encrypted with the team key.
//  Two message types travel on this topic:
//
//    - "hello": "I'm <name>, I'm online" — broadcasts your existence so
//      teammates can populate their roster without prior coordination.
//    - "ping" : "<sender> nudges <to>" — the actual wave. Receivers ignore
//      pings whose `to` doesn't match their own identity.
//

import Foundation
import Combine
import Network
import os

struct NudgePing: Equatable {
    let sender: String
    let message: String?
    let receivedAt: Date
}

/// Wire payload (v2). Carried inside the AES-GCM-encrypted body.
private struct NudgePayload: Codable {
    let v: Int
    let type: String            // "ping" | "hello"
    let sender: String
    let to: String?             // present only on type=="ping"
    let sends: Int              // sender's all-time send total (for the leaderboard)
    let msg: String?            // optional free-text message (ping only); omitted when nil

    static func ping(from sender: String, to recipient: String, sends: Int, msg: String?) -> NudgePayload {
        NudgePayload(v: 2, type: "ping", sender: sender, to: recipient, sends: sends, msg: msg)
    }

    static func hello(from sender: String, sends: Int) -> NudgePayload {
        NudgePayload(v: 2, type: "hello", sender: sender, to: nil, sends: sends, msg: nil)
    }
}

@MainActor
final class NudgeTransport: ObservableObject {
    static let shared = NudgeTransport()

    @Published var lastIncoming: NudgePing?

    private let log = Logger(subsystem: "com.ontora.nudge", category: "transport")
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var currentUser: String?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.ontora.nudge.path")
    private var lastPathStatus: NWPath.Status = .requiresConnection
    private var pathMonitorStarted = false

    /// How often each user broadcasts a fresh "hello" so that rosters
    /// converge even after sleep / network changes.
    private let heartbeatInterval: TimeInterval = 30 * 60

    private init() {}

    // MARK: - Public

    func send(to recipient: String, from sender: String, message: String? = nil) async throws {
        guard let topic = NudgeTeamSecret.shared.teamTopic else {
            log.error("send aborted: no team password set")
            throw URLError(.userAuthenticationRequired)
        }

        // Increment first so the count we broadcast already includes this ping.
        NudgeStats.shared.recordSent(to: recipient)
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = NudgePayload.ping(
            from: sender,
            to: recipient,
            sends: NudgeStats.shared.mySendsTotal,
            msg: (trimmed?.isEmpty == false) ? trimmed : nil
        )
        try await post(payload: payload, to: topic, label: "ping->\(recipient)")
    }

    func startReceiving(as user: String) {
        if currentUser == user, receiveTask != nil { return }
        stopReceiving()
        currentUser = user
        log.info("starting team subscription for \(user)")
        startPathMonitorIfNeeded()

        receiveTask = Task { [weak self] in
            await self?.subscribeLoop(user: user)
        }

        // Announce yourself immediately and on a heartbeat.
        Task { [weak self] in
            await self?.sendHello(as: user)
        }
        heartbeatTask = Task { [weak self] in
            await self?.heartbeatLoop(user: user)
        }
    }

    func stopReceiving() {
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        currentUser = nil
    }

    // MARK: - Subscribe

    private func subscribeLoop(user: String) async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            do {
                try await subscribeOnce(user: user)
                backoff = 1
            } catch is CancellationError {
                return
            } catch {
                log.error("subscribe error: \(error.localizedDescription); retrying in \(backoff)s")
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            backoff = min(backoff * 2, 30)
        }
    }

    private func subscribeOnce(user: String) async throws {
        guard let topic = NudgeTeamSecret.shared.teamTopic else {
            throw URLError(.userAuthenticationRequired)
        }
        let url = URL(string: "https://ntfy.sh/\(topic)/sse")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 0
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        log.info("SSE connected for team topic")

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let raw = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  (json["event"] as? String) == "message",
                  let messageBody = json["message"] as? String,
                  let plaintext = NudgeTeamSecret.shared.decrypt(messageBody),
                  let pdata = plaintext.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(NudgePayload.self, from: pdata) else {
                continue
            }
            await handle(payload: payload, myUser: user)
        }
    }

    private func handle(payload: NudgePayload, myUser: String) async {
        // Anyone we hear from goes into the roster.
        NudgeRoster.shared.record(name: payload.sender)

        switch payload.type {
        case "hello":
            if payload.sends > 0 {
                NudgeStats.shared.recordPeerLeaderboard(
                    peer: payload.sender,
                    totalSends: payload.sends
                )
            }
        case "ping":
            // Ignore pings addressed to other people. Also ignore your
            // own loopback (you'd see your own broadcast otherwise).
            guard let to = payload.to,
                  to == myUser,
                  payload.sender != myUser else { return }
            NudgeStats.shared.recordReceived(from: payload.sender)
            NudgeStats.shared.recordPeerLeaderboard(
                peer: payload.sender,
                totalSends: payload.sends
            )
            self.lastIncoming = NudgePing(sender: payload.sender, message: payload.msg, receivedAt: Date())
        default:
            log.info("ignoring unknown payload type: \(payload.type)")
        }
    }

    // MARK: - Hello / heartbeat

    private func sendHello(as user: String) async {
        guard let topic = NudgeTeamSecret.shared.teamTopic else { return }
        let payload = NudgePayload.hello(from: user, sends: NudgeStats.shared.mySendsTotal)
        do {
            try await post(payload: payload, to: topic, label: "hello")
        } catch {
            log.error("hello send failed: \(error.localizedDescription)")
        }
    }

    private func heartbeatLoop(user: String) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval) * 1_000_000_000)
            if Task.isCancelled { return }
            await sendHello(as: user)
        }
    }

    // MARK: - HTTP helper

    private func post(payload: NudgePayload, to topic: String, label: String) async throws {
        guard let data = try? JSONEncoder().encode(payload),
              let str = String(data: data, encoding: .utf8),
              let body = NudgeTeamSecret.shared.encrypt(str) else {
            log.error("\(label): payload encode/encryption failed")
            throw URLError(.cannotCreateFile)
        }
        let url = URL(string: "https://ntfy.sh/\(topic)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // Generic title — never leak names in cleartext to ntfy's own clients.
        req.setValue("Nudge", forHTTPHeaderField: "Title")
        req.httpBody = Data(body.utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            log.error("\(label) returned \(http.statusCode)")
            throw URLError(.badServerResponse)
        }
        log.info("\(label) ok")
    }

    private func startPathMonitorIfNeeded() {
        guard !pathMonitorStarted else { return }
        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let was = self.lastPathStatus
                self.lastPathStatus = path.status
                if was != .satisfied, path.status == .satisfied,
                   let user = self.currentUser {
                    self.log.info("network became satisfied, resubscribing + saying hello")
                    self.receiveTask?.cancel()
                    self.receiveTask = Task { [weak self] in
                        await self?.subscribeLoop(user: user)
                    }
                    Task { [weak self] in
                        await self?.sendHello(as: user)
                    }
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }
}
