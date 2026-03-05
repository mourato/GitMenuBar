@testable import GitMenuBar
import XCTest

final class GitWorkingTreeStateTests: XCTestCase {
    func testStagedFileAppearsOnlyInStagedSectionWithLineDiff() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        try "base\nstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoURL)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)

        XCTAssertEqual(gitManager.stagedFiles.map(\.path), ["README.md"])
        XCTAssertTrue(gitManager.changedFiles.isEmpty)
        XCTAssertEqual(gitManager.stagedFiles.first?.lineDiff.added, 1)
        XCTAssertEqual(gitManager.stagedFiles.first?.lineDiff.removed, 0)
    }

    func testUnstagedFileAppearsOnlyInChangesSectionWithLineDiff() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        try "base\nunstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)

        XCTAssertTrue(gitManager.stagedFiles.isEmpty)
        XCTAssertEqual(gitManager.changedFiles.map(\.path), ["README.md"])
        XCTAssertEqual(gitManager.changedFiles.first?.lineDiff.added, 1)
        XCTAssertEqual(gitManager.changedFiles.first?.lineDiff.removed, 0)
    }

    func testPartiallyStagedFileAppearsInBothSections() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        try "base\nstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoURL)
        try "base\nstaged\nunstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)

        XCTAssertEqual(gitManager.stagedFiles.map(\.path), ["README.md"])
        XCTAssertEqual(gitManager.changedFiles.map(\.path), ["README.md"])
        XCTAssertEqual(gitManager.stagedFiles.first?.lineDiff.added, 1)
        XCTAssertEqual(gitManager.changedFiles.first?.lineDiff.added, 1)
    }

    func testUntrackedFileReceivesAddedLineCount() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("NEW_FILE.md")

        try "one\ntwo\nthree\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)

        XCTAssertEqual(gitManager.changedFiles.map(\.path), ["NEW_FILE.md"])
        XCTAssertEqual(gitManager.changedFiles.first?.lineDiff.added, 3)
        XCTAssertEqual(gitManager.changedFiles.first?.lineDiff.removed, 0)
    }

    func testBinaryNumstatMapsToNeutralCounts() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("icon.bin")
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        try data.write(to: fileURL)
        try runGit(["add", "icon.bin"], in: repoURL)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)

        XCTAssertEqual(gitManager.stagedFiles.map(\.path), ["icon.bin"])
        XCTAssertEqual(gitManager.stagedFiles.first?.lineDiff.added, 0)
        XCTAssertEqual(gitManager.stagedFiles.first?.lineDiff.removed, 0)
    }

    func testStageAndUnstageFileMovesBetweenSections() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nunstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)
        XCTAssertEqual(gitManager.changedFiles.map(\.path), ["README.md"])
        XCTAssertTrue(gitManager.stagedFiles.isEmpty)

        try waitForGitOperation {
            gitManager.stageFile(path: "README.md", completion: $0)
        }
        let stagedStatus = try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertTrue(stagedStatus.contains("M  README.md"))

        try waitForGitOperation {
            gitManager.unstageFile(path: "README.md", completion: $0)
        }
        let unstagedStatus = try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertTrue(unstagedStatus.contains(" M README.md"))
    }

    func testCommitLocallyCommitsOnlyStagedChanges() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        try "base\nstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoURL)
        try "base\nstaged\nunstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)
        XCTAssertTrue(gitManager.diffStaged().contains("+staged"))

        let expectation = expectation(description: "commit staged only")
        gitManager.commitLocally("feat: staged only") {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)

        let headCount = try runGit(["rev-list", "--count", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(headCount, "2")

        let unstagedDiff = try runGit(["diff", "--", "README.md"], in: repoURL)
        XCTAssertTrue(unstagedDiff.contains("+unstaged"))
    }

    private func waitForWorkingTreeUpdate(_ gitManager: GitManager, timeout: TimeInterval = 3) {
        let expectation = expectation(description: "working tree refresh")
        gitManager.updateUncommittedFiles {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }

    private func waitForGitOperation(
        timeout: TimeInterval = 3,
        operation: (@escaping (Result<Void, Error>) -> Void) -> Void
    ) throws {
        let expectation = expectation(description: "git operation")
        var operationResult: Result<Void, Error>?

        operation { result in
            operationResult = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: timeout)

        if case let .failure(error) = operationResult {
            throw error
        }
    }
}
