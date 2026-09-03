import Foundation

public enum AgentSource: String, Codable, Equatable, Sendable {
    case claudeCode
    case codex
}

public struct AgentHost: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleID: String?
    public var terminalSessionID: String?

    public init(appName: String, bundleID: String? = nil, terminalSessionID: String? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.terminalSessionID = terminalSessionID
    }
}

public enum AgentEventKind: String, Codable, Equatable, Sendable {
    case completion
    case question
    case approval
}

public enum AgentEvent: Codable, Equatable, Sendable {
    case completion(AgentCompletion)
    case question(AgentQuestionSet)
    case approval(AgentApproval)

    public var kind: AgentEventKind {
        switch self {
        case .completion:
            .completion
        case .question:
            .question
        case .approval:
            .approval
        }
    }
}

public struct AgentEventEnvelope: Codable, Equatable, Sendable {
    public var version: Int
    public var source: AgentSource
    public var cwd: String
    public var project: String?
    public var host: AgentHost
    public var event: AgentEvent

    public var kind: AgentEventKind {
        event.kind
    }

    public init(
        version: Int,
        source: AgentSource,
        cwd: String,
        project: String? = nil,
        host: AgentHost,
        event: AgentEvent
    ) {
        self.version = version
        self.source = source
        self.cwd = cwd
        self.project = project
        self.host = host
        self.event = event
    }
}

public struct AgentCompletion: Codable, Equatable, Sendable {
    public var id: String
    public var source: AgentSource
    public var context: String
    public var title: String
    public var message: String?

    public init(
        id: String,
        source: AgentSource,
        context: String,
        title: String,
        message: String? = nil
    ) {
        self.id = id
        self.source = source
        self.context = context
        self.title = title
        self.message = message
    }
}

public struct AgentQuestionSet: Codable, Equatable, Sendable {
    public var id: String
    public var header: String
    public var questions: [AgentQuestion]

    public init(id: String, header: String, questions: [AgentQuestion]) {
        self.id = id
        self.header = header
        self.questions = questions
    }
}

public struct AgentQuestion: Codable, Equatable, Sendable {
    public var id: String
    public var prompt: String
    public var choices: [AgentQuestionChoice]
    public var multiSelect: Bool
    public var allowsFreeform: Bool

    public init(
        id: String,
        prompt: String,
        choices: [AgentQuestionChoice],
        multiSelect: Bool,
        allowsFreeform: Bool
    ) {
        self.id = id
        self.prompt = prompt
        self.choices = choices
        self.multiSelect = multiSelect
        self.allowsFreeform = allowsFreeform
    }
}

public struct AgentQuestionChoice: Codable, Equatable, Sendable {
    public var label: String
    public var description: String

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct AgentApproval: Codable, Equatable, Sendable {
    public var id: String
    public var source: AgentSource
    public var toolName: String
    public var detail: String
    public var command: String?
    public var cwd: String?
    public var allowsClaudeSessionRule: Bool

    public init(
        id: String,
        source: AgentSource,
        toolName: String,
        detail: String,
        command: String? = nil,
        cwd: String? = nil,
        allowsClaudeSessionRule: Bool
    ) {
        self.id = id
        self.source = source
        self.toolName = toolName
        self.detail = detail
        self.command = command
        self.cwd = cwd
        self.allowsClaudeSessionRule = allowsClaudeSessionRule
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
    case multiple([String])
    case text(String)
}

public enum CompletionDisposition: Codable, Equatable, Sendable {
    case displayed
    case discardedWhileRequestIsActive
}
