import Foundation
import Testing
@testable import NudgeAgentCore

struct AgentAttentionStateTests {
    @Test
    func secondInteractiveRequestIsRejectedWithoutQueueing() {
        var state = AgentAttentionState()

        let firstClaim = state.claim(.question(.fixture(id: "first")))
        let secondClaim = state.claim(.approval(.fixture(id: "second")))

        #expect(firstClaim)
        #expect(!secondClaim)
        #expect(state.activeRequest?.id == "first")
    }

    @Test
    func oldCollapseGenerationCannotHideAfterRehover() {
        var state = AgentAttentionState()
        state.visible = true

        let old = state.armCollapse()!
        state.setHovering(true)
        state.setHovering(false)
        let fresh = state.armCollapse()!

        let oldCollapsed = state.collapse(generation: old)
        let freshCollapsed = state.collapse(generation: fresh)

        #expect(!oldCollapsed)
        #expect(freshCollapsed)
    }

    @Test
    func textEditingBlocksCollapseUntilEditingEnds() {
        var state = AgentAttentionState(activeRequest: .question(.fixture(id: "question")))

        state.setEditing(true)
        #expect(state.armCollapse() == nil)

        state.setEditing(false)
        #expect(state.armCollapse() != nil)
    }

    @Test
    func clearingAnEditedRequestDoesNotBlockTheNextCollapse() {
        var state = AgentAttentionState(activeRequest: .question(.fixture(id: "first")))
        state.setEditing(true)

        state.clearRequest(id: "first")
        let claimed = state.claim(.question(.fixture(id: "second")))

        #expect(claimed)
        #expect(!state.isEditing)
        #expect(state.armCollapse() != nil)
    }

    @Test
    func questionDraftSurvivesCollapseAndBackNavigation() {
        var state = AgentAttentionState(activeRequest: .question(.twoQuestionFixture))

        state.answer(.multiple(["A", "B"]), at: 0)
        state.move(to: 1)
        state.answer(.text("because"), at: 1)
        _ = state.collapse(generation: state.armCollapse()!)
        state.move(to: 0)

        #expect(state.drafts[0] == .multiple(["A", "B"]))
        #expect(state.drafts[1] == .text("because"))
    }

    @Test
    func hoverAndEditEntryInvalidateArmedCollapseGenerations() {
        var state = AgentAttentionState()
        state.visible = true

        let hoverGeneration = state.armCollapse()!
        state.setHovering(true)
        state.setHovering(false)

        let editGeneration = state.armCollapse()!
        state.setEditing(true)
        state.setEditing(false)

        let hoverCollapsed = state.collapse(generation: hoverGeneration)
        let editCollapsed = state.collapse(generation: editGeneration)

        #expect(!hoverCollapsed)
        #expect(!editCollapsed)
    }

    @Test
    func claimingInteractiveWorkClearsAnOlderCompletion() {
        var state = AgentAttentionState(completion: completionEnvelope().completion)

        let claimed = state.claim(.question(.fixture(id: "question")))

        #expect(claimed)
        #expect(state.completion == nil)
        #expect(state.activeRequest?.id == "question")
        #expect(state.visible)
    }

    @Test
    func completionDismissalOnlyMatchesTheExpectedIdentifier() {
        var state = AgentAttentionState(completion: completionEnvelope().completion)

        state.dismissCompletion(id: "different")
        #expect(state.completion?.id == "completion")
        #expect(state.visible)

        state.dismissCompletion(id: "completion")
        #expect(state.completion == nil)
        #expect(!state.visible)
    }

    @Test
    func submissionMapsEveryExactPromptToItsAnswerKind() {
        var state = AgentAttentionState(activeRequest: .question(.submissionFixture))

        state.answer(.single("Ship"), at: 0)
        state.answer(.multiple(["Tests", "Docs"]), at: 1)
        state.answer(.text("Keep the first cut compact."), at: 2)

        #expect(state.answersForSubmission() == [
            "Choose the release mode.": "Ship",
            "What should be included?": "Docs, Tests",
            "Anything else?": "Keep the first cut compact."
        ])
    }

    @Test
    func submissionRejectsIncompleteOrEmptyDrafts() {
        var state = AgentAttentionState(activeRequest: .question(.submissionFixture))

        state.answer(.single("Ship"), at: 0)
        state.answer(.multiple([]), at: 1)
        state.answer(.text("   "), at: 2)
        #expect(state.answersForSubmission() == nil)

        state.answer(.multiple(["Docs"]), at: 1)
        #expect(state.answersForSubmission() == nil)

        state.answer(.text("Ready"), at: 2)
        #expect(state.answersForSubmission() != nil)
    }

    @Test
    func multipleSubmissionUsesQuestionOptionOrder() {
        var state = AgentAttentionState(activeRequest: .question(.submissionFixture))

        state.answer(.single("Ship"), at: 0)
        state.answer(.multiple(["Tests", "Docs"]), at: 1)
        state.answer(.text("Ready"), at: 2)

        #expect(state.answersForSubmission()?["What should be included?"] == "Docs, Tests")
    }

    @Test
    func freeformSubmissionWorksForEveryDisplayedQuestion() {
        var state = AgentAttentionState(activeRequest: .question(.twoQuestionFixture))

        state.answer(.text("A custom combination"), at: 0)
        state.answer(.text("Because it fits"), at: 1)

        #expect(state.answersForSubmission() == [
            "Choose every applicable option.": "A custom combination",
            "Explain your choice.": "Because it fits"
        ])
    }

    @Test
    func normalizedEventsRoundTripForAllPayloadKinds() throws {
        let host = AgentHost(appName: "Terminal", bundleID: "com.apple.Terminal", terminalSessionID: "tty-42")
        let question = AgentQuestionSet.fixture(id: "question")
        let approval = AgentApproval.fixture(id: "approval")
        let events = [
            AgentEventEnvelope(
                protocolVersion: 1,
                source: .claudeCode,
                cwd: "/work/nudge",
                project: "nudge",
                host: host,
                event: .completion(.init(
                    id: "completion",
                    source: .claudeCode,
                    context: "Finished the requested change.",
                    title: "Ready for review",
                    message: "Tests pass."
                ))
            ),
            AgentEventEnvelope(
                protocolVersion: 1,
                source: .codex,
                cwd: "/work/nudge",
                project: "nudge",
                host: host,
                event: .question(question)
            ),
            AgentEventEnvelope(
                protocolVersion: 1,
                source: .claudeCode,
                cwd: "/work/nudge",
                project: "nudge",
                host: host,
                event: .approval(approval)
            )
        ]

        for event in events {
            let data = try JSONEncoder().encode(event)
            let decoded = try JSONDecoder().decode(AgentEventEnvelope.self, from: data)

            #expect(decoded == event)
        }

        #expect(events.map(\.kind) == [.completion, .question, .approval])
    }

    @Test
    func completionWireFormatUsesExplicitVersionedPayload() throws {
        let envelope = completionEnvelope()
        let data = try JSONEncoder().encode(envelope)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let event = object?["event"] as? [String: Any]
        let payload = event?["payload"] as? [String: Any]

        #expect(object?["protocolVersion"] as? Int == 1)
        #expect(object?["version"] == nil)
        #expect(event?["type"] as? String == "completion")
        #expect(payload?["id"] as? String == "completion")
        #expect(payload?["_0"] == nil)

        let fixture = Data(
            """
            {
              "protocolVersion": 1,
              "source": "claudeCode",
              "cwd": "/work/nudge",
              "project": "nudge",
              "host": {
                "appName": "Terminal",
                "bundleID": "com.apple.Terminal",
                "terminalSessionID": "tty-42"
              },
              "event": {
                "type": "completion",
                "payload": {
                  "id": "completion",
                  "source": "claudeCode",
                  "context": "Finished the requested change.",
                  "title": "Ready for review",
                  "message": "Tests pass."
                }
              }
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(AgentEventEnvelope.self, from: fixture)

        #expect(decoded == envelope)
    }
}

private func completionEnvelope() -> AgentEventEnvelope {
    AgentEventEnvelope(
        protocolVersion: 1,
        source: .claudeCode,
        cwd: "/work/nudge",
        project: "nudge",
        host: .init(appName: "Terminal", bundleID: "com.apple.Terminal", terminalSessionID: "tty-42"),
        event: .completion(.init(
            id: "completion",
            source: .claudeCode,
            context: "Finished the requested change.",
            title: "Ready for review",
            message: "Tests pass."
        ))
    )
}

private extension AgentEventEnvelope {
    var completion: AgentCompletion? {
        guard case let .completion(completion) = event else { return nil }
        return completion
    }
}

private extension AgentQuestionSet {
    static func fixture(id: String) -> Self {
        .init(
            id: id,
            header: "Agent question",
            questions: [
                .init(
                    id: "question",
                    prompt: "What should happen?",
                    choices: [
                        .init(label: "A", description: "Choose the first option."),
                        .init(label: "B", description: "Choose the second option.")
                    ],
                    multiSelect: false,
                    allowsFreeform: true
                )
            ]
        )
    }

    static let twoQuestionFixture = Self(
        id: "questions",
        header: "Two related questions",
        questions: [
            .init(
                id: "first",
                prompt: "Choose every applicable option.",
                choices: [
                    .init(label: "A", description: "First option."),
                    .init(label: "B", description: "Second option.")
                ],
                multiSelect: true,
                allowsFreeform: false
            ),
            .init(
                id: "second",
                prompt: "Explain your choice.",
                choices: [],
                multiSelect: false,
                allowsFreeform: true
            )
        ]
    )

    static let submissionFixture = Self(
        id: "submission",
        header: "Release questions",
        questions: [
            .init(
                id: "mode",
                prompt: "Choose the release mode.",
                choices: [
                    .init(label: "Draft", description: "Keep iterating."),
                    .init(label: "Ship", description: "Publish the change.")
                ],
                multiSelect: false,
                allowsFreeform: true
            ),
            .init(
                id: "scope",
                prompt: "What should be included?",
                choices: [
                    .init(label: "Docs", description: "Update documentation."),
                    .init(label: "Tests", description: "Run verification."),
                    .init(label: "Demo", description: "Include a demo.")
                ],
                multiSelect: true,
                allowsFreeform: true
            ),
            .init(
                id: "notes",
                prompt: "Anything else?",
                choices: [],
                multiSelect: false,
                allowsFreeform: true
            )
        ]
    )
}

private extension AgentApproval {
    static func fixture(id: String) -> Self {
        .init(
            id: id,
            source: .claudeCode,
            toolName: "Bash",
            detail: "Run the requested command.",
            command: "swift test",
            cwd: "/work/nudge",
            allowsClaudeSessionRule: true
        )
    }
}
