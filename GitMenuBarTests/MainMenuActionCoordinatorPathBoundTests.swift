@testable import GitMenuBar
import XCTest

@MainActor
final class MainMenuActionCoordinatorPathBoundTests: XCTestCase {
    func testCommitStaysBoundToOriginalPathAfterDifferentProjectSelection() async {
        let manager = PathBoundTestGitManager(repositoryPath: "/tmp/project-a")
        manager.changedFiles = [WorkingTreeFile(path: "README.md", lineDiff: .zero, status: .modified)]

        var completedPaths: [String] = []
        let coordinator = makeCoordinator(manager) { path in
            completedPaths.append(path)
        }
        let started = expectation(description: "commit starts")
        manager.commitStarted = started

        let action = Task { @MainActor in
            await coordinator.performCommit(
                commentText: "feat: project a",
                shouldPushAfterCommit: true
            )
        }

        await fulfillment(of: [started])
        XCTAssertFalse(coordinator.canSwitchRepository(to: "/tmp/project-a"))
        XCTAssertTrue(coordinator.canSwitchRepository(to: "/tmp/project-b"))
        let duplicate = await coordinator.performCommit(
            commentText: "feat: duplicate",
            shouldPushAfterCommit: true
        )
        XCTAssertEqual(duplicate, .skipped)
        XCTAssertEqual(manager.commitPaths, ["/tmp/project-a"])
        manager.selectedPath = "/tmp/project-b"
        manager.resetSelectedRepositoryState()
        coordinator.resetForRepositorySwitch()
        manager.releaseCommit()

        let result = await action.value

        XCTAssertEqual(result, .committed)
        XCTAssertEqual(manager.commitPaths, ["/tmp/project-a"])
        XCTAssertEqual(manager.pushPaths, ["/tmp/project-a"])
        XCTAssertEqual(completedPaths, ["/tmp/project-a"])
        XCTAssertNil(coordinator.success)
        XCTAssertNil(coordinator.alert)
        XCTAssertNil(coordinator.operationStatus)
    }

    func testAtomicCommitKeepsProjectSwitchBlockedBecauseItsGitFlowIsNotPathBound() async {
        let manager = PathBoundTestGitManager(repositoryPath: "/tmp/project-a")
        let coordinator = makeCoordinator(manager)
        let started = expectation(description: "atomic commit starts")
        manager.atomicCommitStarted = started

        let action = Task { @MainActor in
            await coordinator.performAtomicCommitsAndPush(groups: [
                AtomicCommitGroup(files: ["README.md"], message: "feat: project a")
            ])
        }

        await fulfillment(of: [started])
        XCTAssertFalse(coordinator.canSwitchRepository(to: "/tmp/project-b"))
        manager.releaseAtomicCommit()
        _ = await action.value
    }

    private func makeCoordinator(
        _ manager: PathBoundTestGitManager,
        onCommitCompleted: (@MainActor (String) -> Void)? = nil
    ) -> MainMenuActionCoordinator {
        let providerStore = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        let apiKeyStore = InMemoryAIAPIKeyStore()
        let aiCoordinator = AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: apiKeyStore,
            messageService: AICommitMessageService(session: makeMockedURLSession()),
            gitManager: manager
        )
        return MainMenuActionCoordinator(
            gitManager: manager,
            aiCommitCoordinator: aiCoordinator,
            onCommitCompleted: onCommitCompleted
        )
    }
}

@MainActor
private final class PathBoundTestGitManager: GitManager {
    var selectedPath: String
    var commitStarted: XCTestExpectation?
    var atomicCommitStarted: XCTestExpectation?
    var commitPaths: [String] = []
    var pushPaths: [String] = []
    private var commitContinuation: CheckedContinuation<Void, Never>?
    private var atomicCommitContinuation: CheckedContinuation<Void, Never>?

    init(repositoryPath: String) {
        selectedPath = repositoryPath
        super.init(repositoryPathOverride: repositoryPath)
    }

    override func isCurrent(_ context: RepositoryOperationContext) -> Bool {
        selectedPath == context.repositoryPath
    }

    override func commitLocallyWithFallbackAsync(
        _: String,
        skipUIUpdates _: Bool = false,
        context: RepositoryOperationContext
    ) async -> Result<Void, Error> {
        commitPaths.append(context.repositoryPath)
        commitStarted?.fulfill()
        commitStarted = nil
        await withCheckedContinuation { continuation in
            commitContinuation = continuation
        }
        return .success(())
    }

    override func pushToRemoteAsync(context: RepositoryOperationContext) async -> Result<Void, Error> {
        pushPaths.append(context.repositoryPath)
        return .success(())
    }

    override func refreshAsync(
        includeReflogHistory _: Bool? = nil,
        context _: RepositoryOperationContext
    ) async {}

    override func checkRemoteStatusAsync(context _: RepositoryOperationContext) async -> Bool {
        false
    }

    override func performAtomicCommitsAsync(
        groups _: [AtomicCommitGroup],
        progress _: ((Int, Int) -> Void)? = nil
    ) async -> Result<Void, Error> {
        atomicCommitStarted?.fulfill()
        atomicCommitStarted = nil
        await withCheckedContinuation { continuation in
            atomicCommitContinuation = continuation
        }
        return .failure(NSError(domain: "Test", code: 1))
    }

    func releaseCommit() {
        commitContinuation?.resume()
        commitContinuation = nil
    }

    func releaseAtomicCommit() {
        atomicCommitContinuation?.resume()
        atomicCommitContinuation = nil
    }
}
