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
    var hasStoredAPIKey: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case endpointURL
        case selectedModel
        case availableModels
        case hasStoredAPIKey
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: AIProviderType,
        endpointURL: String,
        selectedModel: String,
        availableModels: [String] = [],
        hasStoredAPIKey: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.endpointURL = endpointURL
        self.selectedModel = selectedModel
        self.availableModels = availableModels
        self.hasStoredAPIKey = hasStoredAPIKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(AIProviderType.self, forKey: .type)
        endpointURL = try container.decode(String.self, forKey: .endpointURL)
        selectedModel = try container.decode(String.self, forKey: .selectedModel)
        availableModels = try container.decode([String].self, forKey: .availableModels)
        hasStoredAPIKey = try container.decodeIfPresent(Bool.self, forKey: .hasStoredAPIKey) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(endpointURL, forKey: .endpointURL)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(availableModels, forKey: .availableModels)
        try container.encode(hasStoredAPIKey, forKey: .hasStoredAPIKey)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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

enum AIError: LocalizedError, Equatable {
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
