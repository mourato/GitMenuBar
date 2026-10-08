@testable import GitMenuBar
import XCTest

@MainActor
final class GitRepositoryInitServiceTests: XCTestCase {
    func testInitializeAndCommitUsesExplicitPath() throws {
        let directory = try makeTemporaryTestDirectory(testName: #function)
        let service = GitRepositoryInitService(commandRunner: GitCommandRunner())
        XCTAssertFalse(service.isGitRepository(at: directory.path))
        XCTAssertTrue(service.initializeRepository(at: directory.path))
        XCTAssertTrue(service.isGitRepository(at: directory.path))
        try runGit(["config", "user.name", "Test"], in: directory)
        try runGit(["config", "user.email", "test@example.com"], in: directory)
        try "initial\n".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(service.hasUncommittedChanges(at: directory.path))
        XCTAssertTrue(service.createInitialCommit(at: directory.path, message: "Initial"))
        XCTAssertFalse(service.hasUncommittedChanges(at: directory.path))
        XCTAssertEqual(try runGit(["log", "-1", "--format=%s"], in: directory).trimmingCharacters(in: .whitespacesAndNewlines), "Initial")
    }

    func testRemoteSetupUpdateAndPushToLocalRemote() throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        try runGit(["branch", "-M", "main"], in: repository)
        let directory = try makeTemporaryTestDirectory(testName: #function + "-remote")
        let remote = directory.appendingPathComponent("origin.git")
        try runGit(["init", "--bare", remote.path], in: directory)
        let service = GitRepositoryInitService(commandRunner: GitCommandRunner())
        XCTAssertFalse(service.hasRemoteConfigured(at: repository.path))
        XCTAssertTrue(service.addRemote(at: repository.path, url: "/unused/remote"))
        XCTAssertTrue(service.hasRemoteConfigured(at: repository.path))
        XCTAssertTrue(service.updateRemoteURL(at: repository.path, newURL: remote.path))
        XCTAssertEqual(try runGit(["remote", "get-url", "origin"], in: repository).trimmingCharacters(in: .whitespacesAndNewlines), remote.path)
        XCTAssertTrue(service.pushToNewRemote(at: repository.path))
        XCTAssertEqual(try runGit(["rev-parse", "refs/heads/main"], in: remote), try runGit(["rev-parse", "HEAD"], in: repository))
    }

    func testRemoteExistenceWithoutLiveGitHub() async throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        let service = GitRepositoryInitService(commandRunner: GitCommandRunner())
        let missing = await remoteExists(service, at: repository.path)
        XCTAssertFalse(missing)
        XCTAssertTrue(service.addRemote(at: repository.path, url: "https://example.com/owner/repo.git"))
        let nonGitHub = await remoteExists(service, at: repository.path)
        XCTAssertTrue(nonGitHub)
        XCTAssertTrue(service.updateRemoteURL(at: repository.path, newURL: "https://github.com/owner/repo.git"))
        let unavailableClient = await remoteExists(service, at: repository.path)
        XCTAssertTrue(unavailableClient)
    }

    func testInvalidPathReturnsFailure() throws {
        let directory = try makeTemporaryTestDirectory(testName: #function)
        let missing = directory.appendingPathComponent("missing").path
        let service = GitRepositoryInitService(commandRunner: GitCommandRunner())
        XCTAssertFalse(service.initializeRepository(at: missing))
        XCTAssertFalse(service.createInitialCommit(at: missing, message: "Initial"))
        XCTAssertFalse(service.addRemote(at: missing, url: "/unused"))
        XCTAssertFalse(service.updateRemoteURL(at: missing, newURL: "/unused"))
        XCTAssertFalse(service.pushToNewRemote(at: missing))
        XCTAssertFalse(service.hasRemoteConfigured(at: missing))
        XCTAssertFalse(service.hasUncommittedChanges(at: missing))
    }

    private func remoteExists(_ service: GitRepositoryInitService, at path: String) async -> Bool {
        await withCheckedContinuation { continuation in
            service.remoteRepositoryExists(at: path) { continuation.resume(returning: $0) }
        }
    }
}
