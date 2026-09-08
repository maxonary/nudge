import AppKit
import Combine
import Foundation

@MainActor
final class AgentAttentionCenter: ObservableObject {
    static let shared = AgentAttentionCenter()

    @Published private(set) var state = AgentAttentionState()

    private(set) var activeEnvelope: AgentEventEnvelope?
    private(set) var completionEnvelope: AgentEventEnvelope?

    private var activeSession: AgentBridgeSession?
    private var collapseTask: Task<Void, Never>?
    private var lastCompletionID: String?
    private var activationObserver: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.applicationDidActivate(application)
            }
        }
    }

    deinit {
        collapseTask?.cancel()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    var hasVisibleAgentContent: Bool {
        state.visible && (state.activeRequest != nil || state.completion != nil)
    }

    var presentedEnvelope: AgentEventEnvelope? {
        guard state.visible else { return nil }
        return activeEnvelope ?? completionEnvelope
    }

    func receive(_ envelope: AgentEventEnvelope, session: AgentBridgeSession) {
        guard envelope.protocolVersion == 1, payloadMatchesEnvelopeSource(envelope) else {
            finishInvalid(envelope, session: session)
            return
        }

        switch envelope.event {
        case let .completion(completion):
            receiveCompletion(completion, envelope: envelope, session: session)

        case let .question(questionSet):
            guard !questionSet.questions.isEmpty,
                  state.claim(.question(questionSet)) else {
                session.handoff()
                return
            }
            claim(envelope, session: session)

        case let .approval(approval):
            guard state.claim(.approval(approval)) else {
                session.handoff()
                return
            }
            claim(envelope, session: session)
        }
    }

    func disconnect(envelope: AgentEventEnvelope, session: AgentBridgeSession) {
        guard activeEnvelope == envelope, activeSession === session else { return }
        clearActiveRequest(id: envelope.event.requestID)
    }

    func hoverBegan() {
        collapseTask?.cancel()
        collapseTask = nil
        state.setHovering(true)
        if state.activeRequest != nil {
            state.visible = true
        }
    }

    func hoverEnded() {
        state.setHovering(false)
        scheduleCollapseAfterThreeSeconds()
    }

    func beginEditing() {
        collapseTask?.cancel()
        collapseTask = nil
        state.setEditing(true)
    }

    func endEditing() {
        state.setEditing(false)
        scheduleCollapseAfterThreeSeconds()
    }

    func answer(_ answer: AgentAnswer, at index: Int) {
        state.answer(answer, at: index)
    }

    func moveQuestion(to index: Int) {
        state.move(to: index)
    }

    func submitQuestion() {
        guard case let .question(questionSet) = state.activeRequest,
              let answers = state.answersForSubmission(),
              let session = activeSession else {
            return
        }

        activeSession = nil
        activeEnvelope = nil
        cancelCollapse()
        state.clearRequest(id: questionSet.id)
        session.respond(.answered(answers: answers))
    }

    func resolveApproval(_ response: AgentBridgeResponse) {
        guard case let .approval(approval) = state.activeRequest,
              let session = activeSession,
              isValidApprovalResponse(response, for: approval) else {
            return
        }

        activeSession = nil
        activeEnvelope = nil
        cancelCollapse()
        state.clearRequest(id: approval.id)
        session.respond(response)
    }

    func jumpOrHandoff() {
        let envelope = presentedEnvelope

        if let request = state.activeRequest {
            let session = activeSession
            activeSession = nil
            activeEnvelope = nil
            cancelCollapse()
            state.clearRequest(id: request.id)
            session?.handoff()
        } else if let completion = state.completion {
            completionEnvelope = nil
            cancelCollapse()
            state.dismissCompletion(id: completion.id)
        }

        if let host = envelope?.host {
            activate(host: host)
        }
    }

    func jumpLabel(for host: AgentHost) -> String {
        "Zu \(host.appName)"
    }

    @discardableResult
    func showDemo(source: AgentSource) -> Bool {
        guard state.activeRequest == nil else { return false }

        let sourceName = source == .claudeCode ? "Claude Code" : "Codex"
        let completion = AgentCompletion(
            id: "demo-\(UUID().uuidString)",
            source: source,
            context: "nudge",
            title: "\(sourceName) ist fertig",
            message: "Die Aufgabe ist bereit für deinen nächsten Schritt."
        )
        let envelope = AgentEventEnvelope(
            protocolVersion: 1,
            source: source,
            cwd: FileManager.default.currentDirectoryPath,
            project: "nudge",
            host: AgentHost(appName: "Terminal", bundleID: "com.apple.Terminal"),
            event: .completion(completion)
        )

        dismissPresentedCompletion()
        lastCompletionID = completion.id
        completionEnvelope = envelope
        _ = state.receiveCompletion(completion)
        playCompletionSound()
        scheduleCollapseAfterThreeSeconds()
        return true
    }

    private func claim(_ envelope: AgentEventEnvelope, session: AgentBridgeSession) {
        dismissPresentedCompletion()
        activeEnvelope = envelope
        activeSession = session
        scheduleCollapseAfterThreeSeconds()
    }

    private func receiveCompletion(
        _ completion: AgentCompletion,
        envelope: AgentEventEnvelope,
        session: AgentBridgeSession
    ) {
        session.close()
        guard completion.id != lastCompletionID else { return }

        lastCompletionID = completion.id
        playCompletionSound()

        guard state.activeRequest == nil else { return }
        dismissPresentedCompletion()
        guard !isOriginFrontmost(envelope.host) else { return }

        completionEnvelope = envelope
        _ = state.receiveCompletion(completion)
        scheduleCollapseAfterThreeSeconds()
    }

    private func finishInvalid(_ envelope: AgentEventEnvelope, session: AgentBridgeSession) {
        if case .completion = envelope.event {
            session.close()
        } else {
            session.handoff()
        }
    }

    private func payloadMatchesEnvelopeSource(_ envelope: AgentEventEnvelope) -> Bool {
        switch envelope.event {
        case let .completion(completion):
            return completion.source == envelope.source
        case .question:
            return true
        case let .approval(approval):
            return approval.source == envelope.source
                && (!approval.allowsClaudeSessionRule || envelope.source == .claudeCode)
        }
    }

    private func isValidApprovalResponse(
        _ response: AgentBridgeResponse,
        for approval: AgentApproval
    ) -> Bool {
        switch response {
        case .approvedOnce, .denied:
            return true
        case .approvedForSession:
            return approval.source == .claudeCode && approval.allowsClaudeSessionRule
        case .answered:
            return false
        }
    }

    private func scheduleCollapseAfterThreeSeconds() {
        collapseTask?.cancel()
        collapseTask = nil
        guard let generation = state.armCollapse() else { return }

        collapseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.collapse(generation: generation)
        }
    }

    private func collapse(generation: Int) {
        guard state.collapse(generation: generation) else { return }
        collapseTask = nil

        if let completion = state.completion {
            completionEnvelope = nil
            state.dismissCompletion(id: completion.id)
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
        state.cancelCollapse()
    }

    private func dismissPresentedCompletion() {
        guard let completion = state.completion else {
            completionEnvelope = nil
            return
        }
        completionEnvelope = nil
        state.dismissCompletion(id: completion.id)
    }

    private func clearActiveRequest(id: String?) {
        guard let id else { return }
        activeSession = nil
        activeEnvelope = nil
        cancelCollapse()
        state.clearRequest(id: id)
    }

    private func applicationDidActivate(_ application: NSRunningApplication) {
        guard let bundleID = application.bundleIdentifier else { return }

        if activeEnvelope?.host.bundleID == bundleID, let request = state.activeRequest {
            let session = activeSession
            activeSession = nil
            activeEnvelope = nil
            cancelCollapse()
            state.clearRequest(id: request.id)
            session?.handoff()
        }

        if completionEnvelope?.host.bundleID == bundleID,
           let completion = state.completion {
            completionEnvelope = nil
            cancelCollapse()
            state.dismissCompletion(id: completion.id)
        }
    }

    private func isOriginFrontmost(_ host: AgentHost) -> Bool {
        guard let bundleID = host.bundleID else { return false }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private func activate(host: AgentHost) {
        if let bundleID = host.bundleID,
           let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first {
            application.activate(options: [.activateAllWindows])
            return
        }

        if let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == host.appName
        }) {
            application.activate(options: [.activateAllWindows])
        }
    }

    private func playCompletionSound() {
        let storedPreference = UserDefaults.standard.object(forKey: "nudgePlaySoundOnReceive") as? Bool
        guard storedPreference ?? true else { return }
        NSSound(named: NSSound.Name("Pop"))?.play()
    }
}

private extension AgentEvent {
    var requestID: String? {
        switch self {
        case .completion:
            return nil
        case let .question(questionSet):
            return questionSet.id
        case let .approval(approval):
            return approval.id
        }
    }
}
