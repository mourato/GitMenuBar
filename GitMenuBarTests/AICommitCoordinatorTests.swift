@testable import GitMenuBar
import XCTest

@MainActor
final class AICommitCoordinatorTests: XCTestCase {
    func testReadinessUsesStoredAPIKeyAsSourceOfTruth() {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: false)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore(storage: [provider.id: "secret-key"])
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        XCTAssertTrue(coordinator.isReadyForGeneration)
        XCTAssertEqual(coordinator.generationDisabledReason, "")
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, true)
        XCTAssertGreaterThanOrEqual(apiKeyStore.readCount, 1)
    }

    func testSaveAndDeleteAPIKeyUpdatesStoredFlag() {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: false)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore()
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        coordinator.saveAPIKey("secret-key", for: provider.id)
        XCTAssertEqual(apiKeyStore.saveCount, 1)
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, true)

        coordinator.deleteAPIKey(for: provider.id)
        XCTAssertEqual(apiKeyStore.deleteCount, 1)
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, false)
    }

    func testGenerateMessageReadsAPIKeyOnlyWhenInvoked() async {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: true)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore(storage: [provider.id: "secret-key"])
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore,
            repositoryPathOverride: ""
        )

        XCTAssertEqual(apiKeyStore.readCount, 0)

        do {
            _ = try await coordinator.generateMessage(scopeOverride: nil)
            XCTFail("Expected generateMessage to fail without a diff")
        } catch {
            guard let aiError = error as? AIError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(aiError, .noDiffAvailable)
        }

        XCTAssertEqual(apiKeyStore.readCount, 1)
    }

    func testGenerateMessageClearsStoredFlagWhenKeyIsMissing() async {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: true)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore()
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        do {
            _ = try await coordinator.generateMessage(scopeOverride: nil)
            XCTFail("Expected missing API key error")
        } catch {
            guard let aiError = error as? AIError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(aiError, .apiKeyMissing)
        }

        XCTAssertEqual(apiKeyStore.readCount, 1)
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, false)
        XCTAssertEqual(
            coordinator.generationDisabledReason,
            "Add an API key for the default provider in Settings to enable commit generation."
        )
    }

    func testReadinessClearsStoredFlagWhenKeyIsMissing() {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: true)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore()
        let coordinator = makeCoordinator(
            providerStore: providerStore,
            apiKeyStore: apiKeyStore
        )

        XCTAssertFalse(coordinator.isReadyForGeneration)
        XCTAssertEqual(
            coordinator.generationDisabledReason,
            "Add an API key for the default provider in Settings to enable commit generation."
        )
        XCTAssertEqual(providerStore.defaultProvider?.hasStoredAPIKey, false)
    }

    func testGenerateMessageForRawDiffUsesExplicitDiff() async throws {
        let providerStore = makeProviderStore()
        let provider = makeProvider(hasStoredAPIKey: true)
        providerStore.upsertProvider(provider)

        let apiKeyStore = SpyAIAPIKeyStore(storage: [provider.id: "secret-key"])
        let session = makeMockedURLSession()
        var capturedPrompt = ""

        MockURLProtocol.requestHandler = { request in
            let body = self.requestBodyData(from: request)
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                let messages = json["messages"] as? [[String: Any]]
                let userMessage = messages?.first(where: { ($0["role"] as? String) == "user" })
                capturedPrompt = userMessage?["content"] as? String ?? ""
            }

            let response = "{\"choices\":[{\"message\":{\"content\":\"feat: rewritten\"}}]}"
            let data = response.data(using: .utf8) ?? Data()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let coordinator = AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: apiKeyStore,
            messageService: AICommitMessageService(session: session),
            gitManager: GitManager(repositoryPathOverride: "")
        )

        let message = try await coordinator.generateMessage(
            forRawDiff: """
            diff --git a/README.md b/README.md
            --- a/README.md
            +++ b/README.md
            @@ -1 +1,2 @@
             base
            +updated
            """,
            scopeDescription: "Selected commit"
        )

        XCTAssertEqual(message, "feat: rewritten")
        XCTAssertTrue(capturedPrompt.contains("Diff scope used: Selected commit."))
        XCTAssertTrue(capturedPrompt.contains("File: README.md"))
    }

    private func makeProviderStore() -> AIProviderStore {
        AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
    }

    private func makeCoordinator(
        providerStore: AIProviderStore,
        apiKeyStore: any AIAPIKeyStore,
        repositoryPathOverride: String = "/tmp"
    ) -> AICommitCoordinator {
        AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: apiKeyStore,
            messageService: AICommitMessageService(),
            gitManager: GitManager(repositoryPathOverride: repositoryPathOverride)
        )
    }

    private func makeProvider(hasStoredAPIKey: Bool) -> AIProviderConfig {
        AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://api.openai.com",
            selectedModel: "gpt-4.1",
            availableModels: ["gpt-4.1"],
            hasStoredAPIKey: hasStoredAPIKey
        )
    }

    private func requestBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let bodyStream = request.httpBodyStream else {
            return Data()
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(&buffer, maxLength: bufferSize)
            if bytesRead <= 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data
    }
}

private final class SpyAIAPIKeyStore: AIAPIKeyStore {
    private var storage: [UUID: String]

    private(set) var readCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    init(storage: [UUID: String] = [:]) {
        self.storage = storage
    }

    func saveAPIKey(_ apiKey: String, for providerId: UUID) {
        saveCount += 1
        storage[providerId] = apiKey
    }

    func apiKey(for providerId: UUID) -> String? {
        readCount += 1
        return storage[providerId]
    }

    func fetchAllAPIKeys() -> [UUID: String] {
        storage
    }

    func deleteAPIKey(for providerId: UUID) {
        deleteCount += 1
        storage.removeValue(forKey: providerId)
    }
}
