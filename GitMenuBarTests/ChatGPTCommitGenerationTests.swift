@testable import GitMenuBar
import XCTest

@MainActor
final class ChatGPTCommitGenerationTests: XCTestCase {
    func testChatGPTRouteUsesSelectedModelAndReasoningEffort() async throws {
        let generator = StubChatGPTGenerator(response: "feat: use ChatGPT account")
        let service = AICommitMessageService(chatGPTGenerator: generator)

        let message = try await service.generateCommitMessage(
            generation: .chatGPT(model: "gpt-5", reasoningEffort: "high"),
            rawDiff: "+new line"
        )

        XCTAssertEqual(message, "feat: use ChatGPT account")
        XCTAssertEqual(generator.model, "gpt-5")
        XCTAssertEqual(generator.reasoningEffort, "high")
        XCTAssertTrue(generator.prompt.contains("+new line"))
    }

    func testSubscriptionModelParserPreservesEffortsAndDefaults() throws {
        let responseData = Data("""
        {
          "id": 1,
          "result": {
            "data": [
              {
                "model": "gpt-5",
                "displayName": "GPT-5",
                "supportedReasoningEfforts": [
                  {"reasoningEffort": "minimal", "description": "Fast"},
                  {"reasoningEffort": "high", "description": "Deep"}
                ],
                "defaultReasoningEffort": "minimal",
                "isDefault": true
              }
            ]
          }
        }
        """.utf8)
        guard case let .response(_, result) = CodexAppServerProtocol.parse(responseData) else {
            return XCTFail("Expected JSON-RPC response")
        }

        let models = ChatGPTSubscriptionManager.models(from: result)
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(model.id, "gpt-5")
        XCTAssertEqual(model.name, "GPT-5")
        XCTAssertEqual(model.resolvedEffort("high"), "high")
        XCTAssertEqual(model.resolvedEffort("unsupported"), "minimal")
        XCTAssertTrue(model.isDefault)
    }
}

@MainActor
private final class StubChatGPTGenerator: ChatGPTCommitGenerating {
    let response: String
    private(set) var prompt = ""
    private(set) var model = ""
    private(set) var reasoningEffort: String?

    init(response: String) {
        self.response = response
    }

    func generateCommitResponse(prompt: String, model: String, reasoningEffort: String?) async throws -> String {
        await Task.yield()
        self.prompt = prompt
        self.model = model
        self.reasoningEffort = reasoningEffort
        return response
    }
}
