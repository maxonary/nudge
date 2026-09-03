import Foundation

public struct AgentEventEnvelope: Codable, Equatable, Sendable {
    public var id: String
    public var agentID: String
    public var receivedAt: Date

    public init(id: String, agentID: String, receivedAt: Date) {
        self.id = id
        self.agentID = agentID
        self.receivedAt = receivedAt
    }
}

public struct AgentCompletion: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var message: String?

    public init(id: String, title: String, message: String? = nil) {
        self.id = id
        self.title = title
        self.message = message
    }
}

public struct AgentQuestionSet: Codable, Equatable, Sendable {
    public var id: String
    public var questions: [AgentQuestion]

    public init(id: String, questions: [AgentQuestion]) {
        self.id = id
        self.questions = questions
    }
}

public struct AgentQuestion: Codable, Equatable, Sendable {
    public var id: String
    public var prompt: String
    public var choices: [String]

    public init(id: String, prompt: String, choices: [String]) {
        self.id = id
        self.prompt = prompt
        self.choices = choices
    }
}

public struct AgentApproval: Codable, Equatable, Sendable {
    public var id: String
    public var prompt: String

    public init(id: String, prompt: String) {
        self.id = id
        self.prompt = prompt
    }
}

public enum ActiveAgentRequest: Codable, Equatable, Sendable {
    case question(AgentQuestionSet)
    case approval(AgentApproval)

    public var id: String {
        switch self {
        case let .question(questionSet):
            questionSet.id
        case let .approval(approval):
            approval.id
        }
    }
}

public enum AgentAnswer: Codable, Equatable, Sendable {
    case single(String)
    case text(String)
}

public enum CompletionDisposition: Codable, Equatable, Sendable {
    case displayed
    case discardedWhileRequestIsActive
}
