import Foundation

public struct AgentAttentionState: Codable, Equatable, Sendable {
    public private(set) var activeRequest: ActiveAgentRequest?
    public private(set) var completion: AgentCompletion?
    public private(set) var drafts: [AgentAnswer?]
    public private(set) var questionIndex: Int
    public var visible: Bool
    public private(set) var isHovering: Bool
    public private(set) var isEditing: Bool
    public private(set) var collapseGeneration: Int

    public init(
        activeRequest: ActiveAgentRequest? = nil,
        completion: AgentCompletion? = nil
    ) {
        self.activeRequest = activeRequest
        self.completion = completion
        self.drafts = Self.drafts(for: activeRequest)
        self.questionIndex = 0
        self.visible = activeRequest != nil || completion != nil
        self.isHovering = false
        self.isEditing = false
        self.collapseGeneration = 0
    }

    @discardableResult
    public mutating func claim(_ request: ActiveAgentRequest) -> Bool {
        guard activeRequest == nil else { return false }

        activeRequest = request
        completion = nil
        drafts = Self.drafts(for: request)
        questionIndex = 0
        visible = true
        return true
    }

    @discardableResult
    public mutating func receiveCompletion(_ completion: AgentCompletion) -> CompletionDisposition {
        guard activeRequest == nil else { return .discardedWhileRequestIsActive }

        self.completion = completion
        visible = true
        return .displayed
    }

    public mutating func answer(_ answer: AgentAnswer, at index: Int) {
        guard case let .question(questionSet) = activeRequest,
              questionSet.questions.indices.contains(index),
              drafts.indices.contains(index)
        else { return }

        drafts[index] = answer
    }

    public mutating func move(to index: Int) {
        guard case let .question(questionSet) = activeRequest,
              questionSet.questions.indices.contains(index)
        else { return }

        questionIndex = index
    }

    public mutating func armCollapse() -> Int? {
        guard !isHovering, !isEditing, visible else { return nil }
        collapseGeneration += 1
        return collapseGeneration
    }

    public mutating func cancelCollapse() {
        collapseGeneration += 1
    }

    public mutating func setHovering(_ isHovering: Bool) {
        guard self.isHovering != isHovering else { return }

        self.isHovering = isHovering
        if isHovering {
            cancelCollapse()
        }
    }

    public mutating func setEditing(_ isEditing: Bool) {
        guard self.isEditing != isEditing else { return }

        self.isEditing = isEditing
        if isEditing {
            cancelCollapse()
        }
    }

    @discardableResult
    public mutating func collapse(generation: Int) -> Bool {
        guard generation == collapseGeneration, !isHovering, !isEditing else { return false }
        visible = false
        return true
    }

    public mutating func clearRequest(id: String) {
        guard activeRequest?.id == id else { return }

        activeRequest = nil
        drafts = []
        questionIndex = 0
        visible = completion != nil
    }

    public mutating func dismissCompletion(id: String) {
        guard completion?.id == id else { return }

        completion = nil
        if activeRequest == nil {
            visible = false
        }
    }

    public func answersForSubmission() -> [String: String]? {
        guard case let .question(questionSet) = activeRequest,
              !questionSet.questions.isEmpty,
              questionSet.questions.count == drafts.count else {
            return nil
        }

        var answers: [String: String] = [:]
        for (question, draft) in zip(questionSet.questions, drafts) {
            guard !question.prompt.isEmpty, let draft else { return nil }

            let value: String
            switch draft {
            case let .single(label):
                guard !question.multiSelect,
                      question.choices.contains(where: { $0.label == label }),
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                value = label

            case let .multiple(labels):
                guard question.multiSelect, !labels.isEmpty else { return nil }
                let selected = Set(labels)
                let ordered = question.choices
                    .map(\.label)
                    .filter(selected.contains)
                guard selected.count == labels.count,
                      ordered.count == labels.count else {
                    return nil
                }
                value = ordered.joined(separator: ", ")

            case let .text(text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                value = trimmed
            }

            answers[question.prompt] = value
        }

        guard answers.count == questionSet.questions.count else { return nil }
        return answers
    }

    private static func drafts(for request: ActiveAgentRequest?) -> [AgentAnswer?] {
        guard case let .question(questionSet) = request else { return [] }
        return Array(repeating: nil, count: questionSet.questions.count)
    }
}
