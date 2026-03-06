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
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.fileCountText, "1")
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.addedLineCount, 1)
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.removedLineCount, 0)
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
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.fileCountText, "1")
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.addedLineCount, 1)
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.removedLineCount, 0)
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
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.fileCountText, "1")
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.addedLineCount, 1)
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.removedLineCount, 0)
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.fileCountText, "1")
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.addedLineCount, 1)
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.removedLineCount, 0)
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
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.fileCountText, "1")
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.addedLineCount, 3)
        XCTAssertEqual(gitManager.changedFiles.sectionSummary.removedLineCount, 0)
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
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.fileCountText, "1")
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.addedLineCount, 0)
        XCTAssertEqual(gitManager.stagedFiles.sectionSummary.removedLineCount, 0)
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

    func testStageAllChangesStagesTrackedAndUntrackedFiles() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let trackedFile = repoURL.appendingPathComponent("README.md")
        let untrackedFile = repoURL.appendingPathComponent("NEW.md")
        try "base\nchanged\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try "new file\n".write(to: untrackedFile, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)
        XCTAssertTrue(gitManager.stagedFiles.isEmpty)

        try waitForGitOperation {
            gitManager.stageAllChanges(completion: $0)
        }

        let status = try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertTrue(status.contains("M  README.md"))
        XCTAssertTrue(status.contains("A  NEW.md"))
    }

    func testUnstageAllChangesMovesFilesBackToUnstagedSection() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let trackedFile = repoURL.appendingPathComponent("README.md")
        let untrackedFile = repoURL.appendingPathComponent("NEW.md")
        try "base\nchanged\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try "new file\n".write(to: untrackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "-A"], in: repoURL)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)
        XCTAssertEqual(gitManager.stagedFiles.map(\.path), ["NEW.md", "README.md"])
        XCTAssertTrue(gitManager.changedFiles.isEmpty)

        try waitForGitOperation {
            gitManager.unstageAllChanges(completion: $0)
        }

        let status = try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertTrue(status.contains(" M README.md"))
        XCTAssertTrue(status.contains("?? NEW.md"))
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

    func testCommitLocallyWithFallbackAutoStagesWhenNoStagedFilesExist() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let trackedFile = repoURL.appendingPathComponent("README.md")
        let untrackedFile = repoURL.appendingPathComponent("NEW.md")
        try "base\nchanged\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try "new file\n".write(to: untrackedFile, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        waitForWorkingTreeUpdate(gitManager)
        XCTAssertTrue(gitManager.stagedFiles.isEmpty)
        XCTAssertFalse(gitManager.changedFiles.isEmpty)

        let expectation = expectation(description: "fallback commit")
        gitManager.commitLocallyWithFallback("feat: fallback commit") {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        let headCount = try runGit(["rev-list", "--count", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(headCount, "2")

        let status = try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertTrue(status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
