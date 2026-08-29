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
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .gemini:
            "Gemini"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openAI:
            "https://api.openai.com"
        case .anthropic:
            "https://api.anthropic.com"
        case .gemini:
            "https://generativelanguage.googleapis.com"
        }
    }
}

struct AIProviderCredentialID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    var description: String {
        rawValue
    }

    static let openrouter = Self(rawValue: "openrouter")
    static let google = Self(rawValue: "google")
    static let openai = Self(rawValue: "openai")
    static let anthropic = Self(rawValue: "anthropic")

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(provider: AIProviderConfig) {
        let endpoint = URL(string: provider.endpointURL)
        let host = endpoint?.host?.lowercased()
        let isOpenRouter = host == "openrouter.ai" || host?.hasSuffix(".openrouter.ai") == true
        let normalizedEndpoint = endpoint.map { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return (components?.scheme?.lowercased(), components?.host?.lowercased(), components?.port ?? 443, components?.path == "" || components?.path == "/")
        }
        let builtInEndpoint = { (type: AIProviderType) in
            let expected = URLComponents(string: type.defaultEndpoint)
            return normalizedEndpoint?.0 == expected?.scheme?.lowercased()
                && normalizedEndpoint?.1 == expected?.host?.lowercased()
                && normalizedEndpoint?.2 == (expected?.port ?? 443)
                && normalizedEndpoint?.3 == true
        }

        if isOpenRouter {
            self = .openrouter
        } else if provider.type == .gemini, builtInEndpoint(.gemini) {
            self = .google
        } else if provider.type == .openAI, builtInEndpoint(.openAI) {
            self = .openai
        } else if provider.type == .anthropic, builtInEndpoint(.anthropic) {
            self = .anthropic
        } else {
            self = Self(rawValue: "custom:\(provider.id.uuidString.lowercased())")
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
            "Staged"
        case .unstaged:
            "Unstaged"
        case .all:
            "All"
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
    var fallbackProviderId: UUID?
    var fallbackModel: String
    var defaultScopeMode: AICommitDefaultScopeMode

    private enum CodingKeys: String, CodingKey {
        case defaultProviderId
        case defaultModel
        case fallbackProviderId
        case fallbackModel
        case defaultScopeMode
    }

    init(
        defaultProviderId: UUID?,
        defaultModel: String,
        fallbackProviderId: UUID? = nil,
        fallbackModel: String = "",
        defaultScopeMode: AICommitDefaultScopeMode
    ) {
        self.defaultProviderId = defaultProviderId
        self.defaultModel = defaultModel
        self.fallbackProviderId = fallbackProviderId
        self.fallbackModel = fallbackModel
        self.defaultScopeMode = defaultScopeMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultProviderId = try container.decodeIfPresent(UUID.self, forKey: .defaultProviderId)
        defaultModel = try container.decode(String.self, forKey: .defaultModel)
        fallbackProviderId = try container.decodeIfPresent(UUID.self, forKey: .fallbackProviderId)
        fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel) ?? ""
        defaultScopeMode = try container.decode(AICommitDefaultScopeMode.self, forKey: .defaultScopeMode)
    }

    static let `default` = AICommitPreferences(
        defaultProviderId: nil,
        defaultModel: "",
        fallbackProviderId: nil,
        fallbackModel: "",
        defaultScopeMode: .stagedWithFallbackAll
    )
}

enum AIError: LocalizedError, Equatable {
    case providerNotConfigured
    case apiKeyMissing
    case modelNotConfigured
    case fallbackModelNotConfigured
    case noDiffAvailable
    case invalidEndpoint
    case invalidResponse
    case emptyResponse
    case messagePolicyRejected(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:
            "Configure at least one AI provider and choose a default provider in Settings."
        case .apiKeyMissing:
            "Missing API key for the selected AI provider."
        case .modelNotConfigured:
            "Select a model for the selected AI provider in Settings."
        case .fallbackModelNotConfigured:
            "Select a fallback model for the selected fallback provider in Settings."
        case .noDiffAvailable:
            "No diff found for the selected scope."
        case .invalidEndpoint:
            "The provider endpoint URL is invalid."
        case .invalidResponse:
            "The AI provider returned an unexpected response format."
        case .emptyResponse:
            "The AI provider returned an empty message."
        case let .messagePolicyRejected(message):
            message
        case let .requestFailed(message):
            message
        }
    }
}
