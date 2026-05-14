//
//  NudgeTransport.swift
//  Nudge
//

import Foundation
import Combine
import Network
import os

struct NudgePing: Equatable {
    let sender: String
    let receivedAt: Date
}

@MainActor
final class NudgeTransport: ObservableObject {
    static let shared = NudgeTransport()

    @Published var lastIncoming: NudgePing?

    private let log = Logger(subsystem: "com.ontora.nudge", category: "transport")
    private var receiveTask: Task<Void, Never>?
    private var currentSubscribedUser: String?
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.ontora.nudge.path")
    private var lastPathStatus: NWPath.Status = .requiresConnection
    private var pathMonitorStarted = false

    private init() {}

    func send(to recipient: String, from sender: String) async throws {
        let url = URL(string: "https://ntfy.sh/\(ntfyTopic(for: recipient))")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("\(sender) is waving", forHTTPHeaderField: "Title")
        req.httpBody = Data(sender.utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            log.error("send returned \(http.statusCode)")
            throw URLError(.badServerResponse)
        }
        log.info("sent ping to \(recipient) from \(sender)")
    }

    func startReceiving(as user: String) {
        if currentSubscribedUser == user, receiveTask != nil { return }
        stopReceiving()
        currentSubscribedUser = user
        log.info("starting subscription for \(user)")
        startPathMonitorIfNeeded()
        receiveTask = Task { [weak self] in
            await self?.subscribeLoop(user: user)
        }
    }

    func stopReceiving() {
        receiveTask?.cancel()
        receiveTask = nil
        currentSubscribedUser = nil
    }

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
        let url = URL(string: "https://ntfy.sh/\(ntfyTopic(for: user))/sse")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 0
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        log.info("SSE connected for \(user)")
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8) else { continue }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let event = json["event"] as? String ?? ""
                if event != "message" { continue }
                let sender = (json["message"] as? String)
                    ?? (json["title"] as? String)
                    ?? "Someone"
                await MainActor.run {
                    self.lastIncoming = NudgePing(sender: sender, receivedAt: Date())
                }
            }
        }
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
                   let user = self.currentSubscribedUser {
                    self.log.info("network became satisfied, resubscribing")
                    self.receiveTask?.cancel()
                    self.receiveTask = Task { [weak self] in
                        await self?.subscribeLoop(user: user)
                    }
                }
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }
}
