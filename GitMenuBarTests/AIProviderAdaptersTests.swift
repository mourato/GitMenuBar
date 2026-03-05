@testable import GitMenuBar
import XCTest

final class AIProviderAdaptersTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testOpenAIAdapterParsesModelList() async throws {
        let adapter = OpenAIProviderAdapter()
        let session = makeMockedURLSession()
        let config = AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://mock.openai.local",
            selectedModel: ""
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            let data = "{\"data\":[{\"id\":\"gpt-4.1\"},{\"id\":\"gpt-4o-mini\"}]}".data(using: .utf8) ?? Data()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let models = try await adapter.fetchModels(config: config, apiKey: "secret", session: session)
        XCTAssertEqual(models, ["gpt-4.1", "gpt-4o-mini"])
    }

    func testAnthropicAdapterParsesGeneratedText() async throws {
        let adapter = AnthropicProviderAdapter()
        let session = makeMockedURLSession()
        let config = AIProviderConfig(
            name: "Anthropic",
            type: .anthropic,
            endpointURL: "https://mock.anthropic.local",
            selectedModel: "claude-3-5-sonnet"
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/messages")
            let payload = "{\"content\":[{\"type\":\"text\",\"text\":\"feat(core): improve parser\\n\\n- optimize tokenizer\"}]}"
            let data = payload.data(using: .utf8) ?? Data()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let message = try await adapter.generateCommitMessage(
            config: config,
            apiKey: "secret",
            model: "claude-3-5-sonnet",
            prompt: "diff",
            session: session
        )

        XCTAssertTrue(message.contains("feat(core): improve parser"))
    }

    func testGeminiAdapterParsesGeneratedText() async throws {
        let adapter = GeminiProviderAdapter()
        let session = makeMockedURLSession()
        let config = AIProviderConfig(
            name: "Gemini",
            type: .gemini,
            endpointURL: "https://mock.gemini.local",
            selectedModel: "gemini-2.0-flash"
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains(":generateContent") == true)
            let payload = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"fix(ui): align menu spacing\"}]}}]}"
            let data = payload.data(using: .utf8) ?? Data()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let message = try await adapter.generateCommitMessage(
            config: config,
            apiKey: "secret",
            model: "gemini-2.0-flash",
            prompt: "diff",
            session: session
        )

        XCTAssertEqual(message, "fix(ui): align menu spacing")
    }
}
