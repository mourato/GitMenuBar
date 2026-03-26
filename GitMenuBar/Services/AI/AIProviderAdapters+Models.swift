import Foundation

struct OpenAIModelResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let messages: [Message]
}

struct OpenAIChatChoiceMessage: Decodable {
    let content: String
}

struct OpenAIChatChoice: Decodable {
    let message: OpenAIChatChoiceMessage
}

struct OpenAIChatResponse: Decodable {
    let choices: [OpenAIChatChoice]
}

struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

struct AnthropicMessagesRequest: Encodable {
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

struct AnthropicMessagesResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }

    let content: [ContentBlock]
}

struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}

struct GeminiGenerateContentPart: Encodable {
    let text: String
}

struct GeminiGenerateContent: Encodable {
    let parts: [GeminiGenerateContentPart]
}

struct GeminiGenerationConfig: Encodable {
    let temperature: Double
}

struct GeminiGenerateRequest: Encodable {
    let contents: [GeminiGenerateContent]
    let generationConfig: GeminiGenerationConfig
}

struct GeminiGenerateCandidateContentPart: Decodable {
    let text: String
}

struct GeminiGenerateCandidateContent: Decodable {
    let parts: [GeminiGenerateCandidateContentPart]
}

struct GeminiGenerateCandidate: Decodable {
    let content: GeminiGenerateCandidateContent
}

struct GeminiGenerateResponse: Decodable {
    let candidates: [GeminiGenerateCandidate]
}
