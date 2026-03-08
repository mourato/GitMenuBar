import Foundation

protocol AIProviderAdapter {
    func testConnection(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws

    func fetchModels(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws -> [String]

    func generateCommitMessage(
        config: AIProviderConfig,
        apiKey: String,
        model: String,
        prompt: String,
        session: URLSession
    ) async throws -> String
}

enum AIProviderAdapterFactory {
    static func makeAdapter(for providerType: AIProviderType) -> AIProviderAdapter {
        switch providerType {
        case .openAI:
            return OpenAIProviderAdapter()
        case .anthropic:
            return AnthropicProviderAdapter()
        case .gemini:
            return GeminiProviderAdapter()
        }
    }
}

private func makeBaseURL(from endpoint: String) throws -> URL {
    let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let url = URL(string: trimmed)
    else {
        throw AIError.invalidEndpoint
    }
    return url
}

private func requestFailedError(from data: Data, fallback: String) -> AIError {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return .requestFailed(message)
        }

        if let message = json["message"] as? String {
            return .requestFailed(message)
        }
    }

    return .requestFailed(fallback)
}

struct OpenAIProviderAdapter: AIProviderAdapter {
    func testConnection(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws {
        _ = try await fetchModels(config: config, apiKey: apiKey, session: session)
    }

    func fetchModels(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws -> [String] {
        let baseURL = try makeBaseURL(from: config.endpointURL)
        let url = baseURL.appendingPathComponent("v1/models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw requestFailedError(from: data, fallback: "Failed to fetch models")
        }

        let decoded = try JSONDecoder().decode(OpenAIModelResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    func generateCommitMessage(
        config: AIProviderConfig,
        apiKey: String,
        model: String,
        prompt: String,
        session: URLSession
    ) async throws -> String {
        let baseURL = try makeBaseURL(from: config.endpointURL)
        let url = baseURL.appendingPathComponent("v1/chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = OpenAIChatRequest(
            model: model,
            temperature: 0.2,
            messages: [
                .init(role: "system", content: openAISystemPrompt),
                .init(role: "user", content: prompt)
            ]
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw requestFailedError(from: data, fallback: "Failed to generate commit message")
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIError.emptyResponse
        }

        return content
    }

    private var openAISystemPrompt: String {
        "You generate git commit messages in Conventional Commits format. Respond with plain text only. English only."
    }
}

struct AnthropicProviderAdapter: AIProviderAdapter {
    private let anthropicVersion = "2023-06-01"

    func testConnection(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws {
        _ = try await fetchModels(config: config, apiKey: apiKey, session: session)
    }

    func fetchModels(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws -> [String] {
        let baseURL = try makeBaseURL(from: config.endpointURL)
        let url = baseURL.appendingPathComponent("v1/models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw requestFailedError(from: data, fallback: "Failed to fetch models")
        }

        if let decoded = try? JSONDecoder().decode(AnthropicModelsResponse.self, from: data) {
            let models = decoded.data.map(\.id).sorted()
            if !models.isEmpty {
                return models
            }
        }

        return []
    }

    func generateCommitMessage(
        config: AIProviderConfig,
        apiKey: String,
        model: String,
        prompt: String,
        session: URLSession
    ) async throws -> String {
        let baseURL = try makeBaseURL(from: config.endpointURL)
        let url = baseURL.appendingPathComponent("v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let payload = AnthropicMessagesRequest(
            model: model,
            maxTokens: 800,
            temperature: 0.2,
            system: "You generate git commit messages in Conventional Commits format. Return only plain text in English.",
            messages: [
                .init(role: "user", content: prompt)
            ]
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw requestFailedError(from: data, fallback: "Failed to generate commit message")
        }

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        let textBlocks = decoded.content
            .filter { $0.type == "text" }
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !textBlocks.isEmpty else {
            throw AIError.emptyResponse
        }

        return textBlocks
    }
}

struct GeminiProviderAdapter: AIProviderAdapter {
    func testConnection(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws {
        _ = try await fetchModels(config: config, apiKey: apiKey, session: session)
    }

    func fetchModels(
        config: AIProviderConfig,
        apiKey: String,
        session: URLSession
    ) async throws -> [String] {
        let baseURL = try makeBaseURL(from: config.endpointURL)
        var components = URLComponents(url: geminiModelsURL(baseURL: baseURL), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components?.url else {
            throw AIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw requestFailedError(from: data, fallback: "Failed to fetch models")
        }

        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let cleaned = decoded.models.map { model in
            model.name.replacingOccurrences(of: "models/", with: "")
        }

        return cleaned.sorted()
    }

    func generateCommitMessage(
        config: AIProviderConfig,
        apiKey: String,
        model: String,
        prompt: String,
        session: URLSession
    ) async throws -> String {
        let baseURL = try makeBaseURL(from: config.endpointURL)
        var components = URLComponents(url: geminiGenerateURL(baseURL: baseURL, model: model), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components?.url else {
            throw AIError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = GeminiGenerateRequest(
            contents: [
                .init(parts: [.init(text: geminiSystemPrompt + "\n\n" + prompt)])
            ],
            generationConfig: .init(temperature: 0.2)
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw requestFailedError(from: data, fallback: "Failed to generate commit message")
        }

        let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: data)
        let text = decoded.candidates
            .first?
            .content
            .parts
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !text.isEmpty else {
            throw AIError.emptyResponse
        }

        return text
    }

    private var geminiSystemPrompt: String {
        "Generate a Conventional Commits message in English. Return plain text only and no markdown."
    }

    private func geminiModelsURL(baseURL: URL) -> URL {
        let endpoint = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if endpoint.contains("/v1") {
            return URL(string: endpoint + "/models") ?? baseURL
        }
        return URL(string: endpoint + "/v1beta/models") ?? baseURL
    }

    private func geminiGenerateURL(baseURL: URL, model: String) -> URL {
        let trimmedModel = model.hasPrefix("models/") ? model : "models/\(model)"
        let endpoint = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if endpoint.contains("/v1") {
            return URL(string: endpoint + "/\(trimmedModel):generateContent") ?? baseURL
        }

        return URL(string: endpoint + "/v1beta/\(trimmedModel):generateContent") ?? baseURL
    }
}

private struct OpenAIModelResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let messages: [Message]
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

private struct AnthropicMessagesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

private struct AnthropicMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }

    let content: [ContentBlock]
}

private struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

private struct GeminiGenerateRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String
        }

        let parts: [Part]
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
    }

    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct GeminiGenerateResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String
            }

            let parts: [Part]
        }

        let content: Content
    }

    let candidates: [Candidate]
}
