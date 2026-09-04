@testable import GitMenuBar
import XCTest

// swiftlint:disable file_length

@MainActor
final class MainMenuActionCoordinatorTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRepositorySwitchStaysBlockedForUnboundBusyAction() {
        let gitManager = GitManager(repositoryPathOverride: "")
        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        XCTAssertTrue(actionCoordinator.canSwitchRepository)

        gitManager.isCommitting = true

        XCTAssertFalse(actionCoordinator.canSwitchRepository)
        XCTAssertFalse(actionCoordinator.canSwitchRepository(to: "/tmp/project-b"))
    }

    func testInspectorPushIsSkippedWhileBusy() async {
        let gitManager = GitManager(repositoryPathOverride: "")
        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )
        gitManager.isCommitting = true
        let result = await actionCoordinator.pushInspectorBranch("main")
        XCTAssertEqual(result, .skipped)
    }

    func testFailedInspectorApplyDoesNotReportSuccess() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        try "base\n".write(to: repoURL.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "note.txt"], in: repoURL)
        try runGit(["commit", "-m", "feat: note"], in: repoURL)
        try "stashed\n".write(to: repoURL.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        try runGit(["stash", "push", "-m", "keep-me"], in: repoURL)
        try "conflicting\n".write(to: repoURL.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await gitManager.loadSelectedStashesAsync()
        let hash = try XCTUnwrap(gitManager.stashes.first?.hash)
        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.applyInspectorStash(hash: hash)
        XCTAssertEqual(result, .failed)
        XCTAssertNotNil(actionCoordinator.alert)
        XCTAssertNil(actionCoordinator.success)
        XCTAssertEqual(gitManager.stashService.listStashes(in: repoURL.path).map(\.hash), [hash])
    }

    func testInspectorApplyDoesNotPublishIntoSwitchedProject() async {
        let manager = InspectorGateGitManager(repositoryPath: "/tmp/project-a")
        let coordinator = makeActionCoordinator(
            gitManager: manager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )
        let started = expectation(description: "apply starts")
        manager.applyStarted = started

        let action = Task { @MainActor in
            await coordinator.applyInspectorStash(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        }
        await fulfillment(of: [started])
        let duplicate = await coordinator.applyInspectorStash(hash: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        XCTAssertEqual(duplicate, .skipped)
        manager.selectedPath = "/tmp/project-b"
        manager.resetSelectedRepositoryState()
        coordinator.resetForRepositorySwitch()
        manager.releaseApply(.failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "apply failed"])))

        let result = await action.value
        XCTAssertEqual(result, .failed)
        XCTAssertEqual(manager.applyPaths, ["/tmp/project-a"])
        XCTAssertNil(coordinator.alert)
        XCTAssertNil(coordinator.success)
    }

    func testPerformCommitUsesManualMessageWithoutInvokingAI() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nmanual-change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        let providerStore = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        let apiKeyStore = SpyAIAPIKeyStore()
        var refreshedPaths: [String] = []
        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: providerStore,
            apiKeyStore: apiKeyStore,
            session: makeMockedURLSession(),
            onCommitCompleted: { path in refreshedPaths.append(path) }
        )

        let result = await actionCoordinator.performCommit(commentText: "feat: manual commit")

        XCTAssertEqual(result, .committed)
        XCTAssertEqual(apiKeyStore.readCount, 0)
        XCTAssertNil(actionCoordinator.alert)
        XCTAssertEqual(refreshedPaths, [repoURL.path])

        let headMessage = try runGit(["log", "-1", "--pretty=%B"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(headMessage, "feat: manual commit")
    }

    func testAtomicCommitsRefreshOnceAfterTheLastCommit() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let alphaFile = repoURL.appendingPathComponent("alpha.swift")
        let betaFile = repoURL.appendingPathComponent("beta.swift")
        try "base\n".write(to: alphaFile, atomically: true, encoding: .utf8)
        try "base\n".write(to: betaFile, atomically: true, encoding: .utf8)
        try "base\nalpha\n".write(to: alphaFile, atomically: true, encoding: .utf8)
        try "base\nbeta\n".write(to: betaFile, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        var refreshedPaths: [String] = []
        var observedCommitCount: String?
        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession(),
            onCommitCompleted: { path in
                refreshedPaths.append(path)
                observedCommitCount = try? runGit(["rev-list", "--count", "HEAD"], in: repoURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )

        let result = await actionCoordinator.performAtomicCommitsAndPush(groups: [
            AtomicCommitGroup(files: ["alpha.swift"], message: "feat: alpha"),
            AtomicCommitGroup(files: ["beta.swift"], message: "feat: beta")
        ])

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(refreshedPaths, [repoURL.path])
        XCTAssertEqual(observedCommitCount, "3")
    }

    func testPerformCommitGeneratesMessageWhenInputIsEmpty() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nauto-change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        let providerStore = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        let provider = AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://mock.openai.local",
            selectedModel: "gpt-4.1",
            hasStoredAPIKey: true
        )
        providerStore.upsertProvider(provider)

        let apiKeyStore = InMemoryAIAPIKeyStore()
        try? apiKeyStore.saveAPIKey("test-key", for: AIProviderCredentialID(provider: provider))

        MockURLProtocol.requestHandler = { request in
            let response = "{\"choices\":[{\"message\":{\"content\":\"feat: generated by ai\"}}]}"
            let data = response.data(using: .utf8) ?? Data()
            return try (
                makeMockHTTPResponse(for: request),
                data
            )
        }

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: providerStore,
            apiKeyStore: apiKeyStore,
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performCommit(commentText: "")

        XCTAssertEqual(result, .committed)
        XCTAssertNil(actionCoordinator.alert)

        let headMessage = try runGit(["log", "-1", "--pretty=%B"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(headMessage, "feat: generated by ai")
    }

    func testPerformCommitWithWhitespaceOnlyInputRequestsUserDecision() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nwhitespace-only\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performCommit(commentText: "   \n")

        XCTAssertEqual(result, .skipped)
        XCTAssertNil(actionCoordinator.alert)
        XCTAssertEqual(actionCoordinator.whitespaceCommitPrompt?.rawCommentText, "   \n")
        XCTAssertEqual(actionCoordinator.whitespaceCommitPrompt?.shouldPushAfterCommit, false)

        let headMessage = try runGit(["log", "-1", "--pretty=%B"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(headMessage, "chore: initial")
    }

    func testCommitUsingCurrentWhitespaceMessagePreservesRawWhitespace() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nmanual-whitespace\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        _ = await actionCoordinator.performCommit(commentText: "   \n")
        let result = await actionCoordinator.commitUsingCurrentWhitespaceMessage("   \n")

        XCTAssertEqual(result, .committed)
        XCTAssertNil(actionCoordinator.alert)
        XCTAssertNil(actionCoordinator.whitespaceCommitPrompt)

        let headMessage = try runGit(["log", "-1", "--pretty=%B"], in: repoURL)
        XCTAssertEqual(headMessage, "   \n\n")
    }

    func testCommitByGeneratingMessageAfterDiscardingWhitespaceUsesAI() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\ngenerated-after-whitespace\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        let providerStore = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        let provider = AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://mock.openai.local",
            selectedModel: "gpt-4.1",
            hasStoredAPIKey: true
        )
        providerStore.upsertProvider(provider)

        let apiKeyStore = InMemoryAIAPIKeyStore()
        try? apiKeyStore.saveAPIKey("test-key", for: AIProviderCredentialID(provider: provider))

        MockURLProtocol.requestHandler = { request in
            let response = "{\"choices\":[{\"message\":{\"content\":\"feat: whitespace discarded\"}}]}"
            let data = response.data(using: .utf8) ?? Data()
            return try (
                makeMockHTTPResponse(for: request),
                data
            )
        }

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: providerStore,
            apiKeyStore: apiKeyStore,
            session: makeMockedURLSession()
        )

        _ = await actionCoordinator.performCommit(commentText: "   \n")
        let result = await actionCoordinator.commitByGeneratingMessage(
            afterDiscardingWhitespace: "   \n"
        )

        XCTAssertEqual(result, .committed)
        XCTAssertNil(actionCoordinator.alert)
        XCTAssertNil(actionCoordinator.whitespaceCommitPrompt)

        let headMessage = try runGit(["log", "-1", "--pretty=%B"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(headMessage, "feat: whitespace discarded")
    }

    func testPerformSyncOpensOptionsWhenRemoteIsAhead() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        await waitForWorkingTreeUpdate(gitManager)
        gitManager.isRemoteAhead = true
        gitManager.isAheadOfRemote = true

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore()),
            apiKeyStore: InMemoryAIAPIKeyStore(),
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performSync()

        XCTAssertEqual(result, .requiresOptions)
        XCTAssertTrue(actionCoordinator.showSyncOptions)
    }

    func testPerformCommitAndPushOpensSyncOptionsWhenRemoteIsAhead() async throws {
        let remoteDirectory = try makeTemporaryTestDirectory(testName: #function)

        let remoteURL = remoteDirectory.appendingPathComponent("origin.git")
        try runGit(["init", "--bare", remoteURL.path], in: remoteDirectory)

        let localRepoURL = try createTemporaryGitRepository(testName: #function + "-local")
        try runGit(["remote", "add", "origin", remoteURL.path], in: localRepoURL)
        try runGit(["push", "-u", "origin", "HEAD"], in: localRepoURL)

        let peerCloneURL = remoteDirectory.appendingPathComponent("peer")
        try runGit(["clone", remoteURL.path, peerCloneURL.path], in: remoteDirectory)
        try runGit(["config", "user.email", "test@example.com"], in: peerCloneURL)
        try runGit(["config", "user.name", "GitMenuBar Tests"], in: peerCloneURL)

        let peerFileURL = peerCloneURL.appendingPathComponent("REMOTE.md")
        try "remote advance\n".write(to: peerFileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "REMOTE.md"], in: peerCloneURL)
        try runGit(["commit", "-m", "feat: remote advance"], in: peerCloneURL)
        try runGit(["push"], in: peerCloneURL)

        let localFileURL = localRepoURL.appendingPathComponent("README.md")
        try "base\nlocal commit needed\n".write(to: localFileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: localRepoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        let providerStore = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        let provider = AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://mock.openai.local",
            selectedModel: "gpt-4.1",
            hasStoredAPIKey: true
        )
        providerStore.upsertProvider(provider)

        let apiKeyStore = InMemoryAIAPIKeyStore()
        try? apiKeyStore.saveAPIKey("test-key", for: AIProviderCredentialID(provider: provider))

        MockURLProtocol.requestHandler = { request in
            let response = "{\"choices\":[{\"message\":{\"content\":\"feat: local generated\"}}]}"
            let data = response.data(using: .utf8) ?? Data()
            return try (
                makeMockHTTPResponse(for: request),
                data
            )
        }

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: providerStore,
            apiKeyStore: apiKeyStore,
            session: makeMockedURLSession()
        )

        let result = await actionCoordinator.performCommit(
            commentText: "",
            shouldPushAfterCommit: true
        )

        XCTAssertEqual(result, .committedAndNeedsSyncOptions)
        XCTAssertTrue(actionCoordinator.showSyncOptions)
        XCTAssertNil(actionCoordinator.alert)
    }

    func testWhitespacePromptSupportsCommitAndPushFlow() async throws {
        let remoteDirectory = try makeTemporaryTestDirectory(testName: #function)

        let remoteURL = remoteDirectory.appendingPathComponent("origin.git")
        try runGit(["init", "--bare", remoteURL.path], in: remoteDirectory)

        let localRepoURL = try createTemporaryGitRepository(testName: #function + "-local")
        try runGit(["remote", "add", "origin", remoteURL.path], in: localRepoURL)
        try runGit(["push", "-u", "origin", "HEAD"], in: localRepoURL)

        let peerCloneURL = remoteDirectory.appendingPathComponent("peer")
        try runGit(["clone", remoteURL.path, peerCloneURL.path], in: remoteDirectory)
        try runGit(["config", "user.email", "test@example.com"], in: peerCloneURL)
        try runGit(["config", "user.name", "GitMenuBar Tests"], in: peerCloneURL)

        let peerFileURL = peerCloneURL.appendingPathComponent("REMOTE.md")
        try "remote advance\n".write(to: peerFileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "REMOTE.md"], in: peerCloneURL)
        try runGit(["commit", "-m", "feat: remote advance"], in: peerCloneURL)
        try runGit(["push"], in: peerCloneURL)

        let localFileURL = localRepoURL.appendingPathComponent("README.md")
        try "base\nlocal whitespace prompt\n".write(to: localFileURL, atomically: true, encoding: .utf8)

        let providerStore = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        let provider = AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://mock.openai.local",
            selectedModel: "gpt-4.1",
            hasStoredAPIKey: true
        )
        providerStore.upsertProvider(provider)

        let apiKeyStore = InMemoryAIAPIKeyStore()
        try? apiKeyStore.saveAPIKey("test-key", for: AIProviderCredentialID(provider: provider))

        MockURLProtocol.requestHandler = { request in
            let response = "{\"choices\":[{\"message\":{\"content\":\"feat: whitespace push\"}}]}"
            let data = response.data(using: .utf8) ?? Data()
            return try (
                makeMockHTTPResponse(for: request),
                data
            )
        }

        let gitManager = GitManager(repositoryPathOverride: localRepoURL.path)
        await waitForWorkingTreeUpdate(gitManager)

        let actionCoordinator = makeActionCoordinator(
            gitManager: gitManager,
            providerStore: providerStore,
            apiKeyStore: apiKeyStore,
            session: makeMockedURLSession()
        )

        let promptResult = await actionCoordinator.performCommit(
            commentText: "   \n",
            shouldPushAfterCommit: true
        )

        XCTAssertEqual(promptResult, .skipped)
        XCTAssertEqual(actionCoordinator.whitespaceCommitPrompt?.shouldPushAfterCommit, true)

        let commitResult = await actionCoordinator.commitByGeneratingMessage(
            afterDiscardingWhitespace: "   \n",
            shouldPushAfterCommit: true
        )

        XCTAssertEqual(commitResult, .committedAndNeedsSyncOptions)
        XCTAssertTrue(actionCoordinator.showSyncOptions)
        XCTAssertNil(actionCoordinator.alert)
    }

    func makeActionCoordinator(
        gitManager: GitManager,
        providerStore: AIProviderStore,
        apiKeyStore: any AIAPIKeyStore,
        session: URLSession,
        onCommitCompleted: (@MainActor (String) -> Void)? = nil
    ) -> MainMenuActionCoordinator {
        let aiCoordinator = AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: apiKeyStore,
            messageService: AICommitMessageService(session: session),
            gitManager: gitManager
        )

        return MainMenuActionCoordinator(
            gitManager: gitManager,
            aiCommitCoordinator: aiCoordinator,
            onCommitCompleted: onCommitCompleted
        )
    }

    func waitForWorkingTreeUpdate(_ gitManager: GitManager, timeout: TimeInterval = 3) async {
        let expectation = expectation(description: "working tree refresh")
        gitManager.updateUncommittedFiles {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: timeout)
    }
}

private final class SpyAIAPIKeyStore: AIAPIKeyStore, @unchecked Sendable {
    private var storage: [AIProviderCredentialID: String]

    private(set) var readCount = 0

    init(storage: [AIProviderCredentialID: String] = [:]) {
        self.storage = storage
    }

    func saveAPIKey(_ apiKey: String, for providerId: AIProviderCredentialID) throws {
        storage[providerId] = apiKey
    }

    func apiKey(for providerId: AIProviderCredentialID) throws -> String? {
        readCount += 1
        return storage[providerId]
    }

    func fetchAllAPIKeys() throws -> [AIProviderCredentialID: String] {
        storage
    }

    func replaceAPIKeys(_ values: [AIProviderCredentialID: String]) throws {
        storage = values
    }

    func deleteAPIKey(for providerId: AIProviderCredentialID) throws {
        storage.removeValue(forKey: providerId)
    }
}

@MainActor
private final class InspectorGateGitManager: GitManager {
    var selectedPath: String
    var applyStarted: XCTestExpectation?
    var applyPaths: [String] = []
    private var applyContinuation: CheckedContinuation<Result<Void, Error>, Never>?

    init(repositoryPath: String) {
        selectedPath = repositoryPath
        super.init(repositoryPathOverride: repositoryPath)
    }

    override func isCurrent(_ context: RepositoryOperationContext) -> Bool {
        selectedPath == context.repositoryPath
    }

    override func applyStashAsync(
        hash _: String,
        context: RepositoryOperationContext
    ) async -> Result<Void, Error> {
        applyPaths.append(context.repositoryPath)
        applyStarted?.fulfill()
        applyStarted = nil
        return await withCheckedContinuation { continuation in
            applyContinuation = continuation
        }
    }

    override func refreshAsync(includeReflogHistory _: Bool? = nil) async {}

    override func refreshAsync(
        includeReflogHistory _: Bool? = nil,
        context _: RepositoryOperationContext
    ) async {}

    override func loadSelectedStashesAsync() async {}

    func releaseApply(_ result: Result<Void, Error>) {
        applyContinuation?.resume(returning: result)
        applyContinuation = nil
    }
}
