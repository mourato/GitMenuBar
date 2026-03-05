import Foundation

enum AIProviderType: String, CaseIterable, Codable, Identifiable {
    case openAI = "openai"
    case anthropic
    case gemini

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAI:
            return "https://api.openai.com"
        case .anthropic:
            return "https://api.anthropic.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com"
        }
    }
}

enum DiffScope: String, CaseIterable, Codable, Identifiable {
    case staged
    case unstaged
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .staged:
            return "Staged"
        case .unstaged:
            return "Unstaged"
        case .all:
            return "All"
        }
    }
}

enum AICommitDefaultScopeMode: String, Codable {
    case stagedWithFallbackAll
}

struct AIProviderConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: AIProviderType
    var endpointURL: String
    var selectedModel: String
    var availableModels: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: AIProviderType,
        endpointURL: String,
        selectedModel: String,
        availableModels: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpointURL = endpointURL
        self.selectedModel = selectedModel
        self.availableModels = availableModels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AICommitPreferences: Codable, Equatable {
    var defaultProviderId: UUID?
    var defaultModel: String
    var defaultScopeMode: AICommitDefaultScopeMode

    static let `default` = AICommitPreferences(
        defaultProviderId: nil,
        defaultModel: "",
        defaultScopeMode: .stagedWithFallbackAll
    )
}

enum AIError: LocalizedError {
    case providerNotConfigured
    case apiKeyMissing
    case modelNotConfigured
    case noDiffAvailable
    case invalidEndpoint
    case invalidResponse
    case emptyResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            return "Configure at least one AI provider and choose a default provider in Settings."
        case .apiKeyMissing:
            return "Missing API key for the selected AI provider."
        case .modelNotConfigured:
            return "Select a model for the selected AI provider in Settings."
        case .noDiffAvailable:
            return "No diff found for the selected scope."
        case .invalidEndpoint:
            return "The provider endpoint URL is invalid."
        case .invalidResponse:
            return "The AI provider returned an unexpected response format."
        case .emptyResponse:
            return "The AI provider returned an empty message."
        case let .requestFailed(message):
            return message
        }
    }
}
