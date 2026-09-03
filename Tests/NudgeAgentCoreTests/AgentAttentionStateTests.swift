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
        state.cancelCollapse()
        let fresh = state.armCollapse()!

        let oldCollapsed = state.collapse(generation: old)
        let freshCollapsed = state.collapse(generation: fresh)

        #expect(!oldCollapsed)
        #expect(freshCollapsed)
    }

    @Test
    func questionDraftSurvivesCollapseAndBackNavigation() {
        var state = AgentAttentionState(activeRequest: .question(.twoQuestionFixture))

        state.answer(.single("A"), at: 0)
        state.move(to: 1)
        state.answer(.text("because"), at: 1)
        _ = state.collapse(generation: state.armCollapse()!)
        state.move(to: 0)

        #expect(state.drafts[0] == .single("A"))
        #expect(state.drafts[1] == .text("because"))
    }
}

private extension AgentQuestionSet {
    static func fixture(id: String) -> Self {
        .init(
            id: id,
            questions: [.init(id: "question", prompt: "What should happen?", choices: ["A", "B"])]
        )
    }

    static let twoQuestionFixture = Self(
        id: "questions",
        questions: [
            .init(id: "first", prompt: "Choose", choices: ["A", "B"]),
            .init(id: "second", prompt: "Explain", choices: [])
        ]
    )
}

private extension AgentApproval {
    static func fixture(id: String) -> Self {
        .init(id: id, prompt: "May the agent continue?")
    }
}
