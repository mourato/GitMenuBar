@testable import GitMenuBar
import XCTest

@MainActor
final class AICommitRecoveryTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSecondGenerationFailureDisablesAutomaticRetry() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try "base\nchange\n".write(
            to: repoURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        let providerStore = configuredProviderStore(models: ["primary"])
        let provider = try XCTUnwrap(providerStore.defaultProvider)
        let apiKeyStore = InMemoryAIAPIKeyStore()
        try apiKeyStore.saveAPIKey("test-key", for: AIProviderCredentialID(provider: provider))

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)
            else {
                throw NSError(domain: "Test", code: 1)
            }
            return (response, Data("{\"error\":{\"message\":\"model unavailable\"}}".utf8))
        }

        let aiCoordinator = AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: apiKeyStore,
            messageService: AICommitMessageService(session: makeMockedURLSession()),
            gitManager: gitManager
        )
        let actionCoordinator = MainMenuActionCoordinator(
            gitManager: gitManager,
            aiCommitCoordinator: aiCoordinator
        )

        let firstResult = await actionCoordinator.performCommit(commentText: "")
        XCTAssertEqual(firstResult, .failed)
        XCTAssertTrue(aiCoordinator.automaticRetryAvailable)

        let retryResult = await actionCoordinator.retryAutomaticCommit()
        XCTAssertEqual(retryResult, .failed)
        XCTAssertFalse(aiCoordinator.automaticRetryAvailable)
        XCTAssertEqual(actionCoordinator.alert?.message, "model unavailable")
    }

    func testFallbackModelCommitsAfterSelectedModelFails() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try "base\nchange\n".write(
            to: repoURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        let providerStore = configuredProviderStore(models: ["primary", "fallback"])
        providerStore.updateFallbackModel("fallback")
        let provider = try XCTUnwrap(providerStore.defaultProvider)
        let apiKeyStore = InMemoryAIAPIKeyStore()
        try apiKeyStore.saveAPIKey("test-key", for: AIProviderCredentialID(provider: provider))
        let requestedModels = PromptListCapture()
        let requestCount = PromptListCapture()

        MockURLProtocol.requestHandler = { request in
            requestCount.append("request")
            let body = requestBodyData(from: request)
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let model = json["model"] as? String
            {
                requestedModels.append(model)
            }

            guard let url = request.url else {
                throw NSError(domain: "Test", code: 1)
            }
            if requestCount.values.count == 1 {
                guard let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil) else {
                    throw NSError(domain: "Test", code: 1)
                }
                return (response, Data("{\"error\":{\"message\":\"primary unavailable\"}}".utf8))
            }

            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                throw NSError(domain: "Test", code: 1)
            }
            return (response, Data("{\"choices\":[{\"message\":{\"content\":\"feat: fallback works\"}}]}".utf8))
        }

        let aiCoordinator = AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: apiKeyStore,
            messageService: AICommitMessageService(session: makeMockedURLSession()),
            gitManager: gitManager
        )
        let actionCoordinator = MainMenuActionCoordinator(
            gitManager: gitManager,
            aiCommitCoordinator: aiCoordinator
        )

        let firstResult = await actionCoordinator.performCommit(commentText: "")
        XCTAssertEqual(firstResult, .failed)
        let fallbackResult = await actionCoordinator.commitUsingFallbackModel()
        XCTAssertEqual(fallbackResult, .committed)
        XCTAssertEqual(requestedModels.values, ["primary", "fallback"])
        XCTAssertNil(actionCoordinator.alert)
        XCTAssertEqual(
            try runGit(["log", "-1", "--pretty=%B"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines),
            "feat: fallback works"
        )
    }

    private func configuredProviderStore(models: [String]) -> AIProviderStore {
        let store = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        store.upsertProvider(
            AIProviderConfig(
                name: "OpenAI",
                type: .openAI,
                endpointURL: "https://mock.openai.local",
                selectedModel: models[0],
                availableModels: models
            )
        )
        return store
    }

    private func waitForWorkingTreeUpdate(_ gitManager: GitManager, timeout: TimeInterval = 3) async {
        let expectation = expectation(description: "working tree refresh")
        gitManager.updateUncommittedFiles {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: timeout)
    }
}
