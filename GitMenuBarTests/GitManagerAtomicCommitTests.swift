@testable import GitMenuBar
import XCTest

final class GitManagerAtomicCommitTests: XCTestCase {
    func testDiffForChangedFilesAsyncReturnsExpectedMap() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        let initialExpectation = expectation(description: "working tree refresh")
        gitManager.updateUncommittedFiles { initialExpectation.fulfill() }
        wait(for: [initialExpectation], timeout: 3)

        try "base\nchanged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let refreshExpectation = expectation(description: "working tree refresh after edit")
        gitManager.updateUncommittedFiles { refreshExpectation.fulfill() }
        wait(for: [refreshExpectation], timeout: 3)

        let diffs = await gitManager.diffForChangedFilesAsync()

        XCTAssertEqual(diffs.keys.sorted(), ["README.md"])
        XCTAssertTrue(diffs["README.md"]?.contains("+changed") ?? false)
    }

    func testCommitAtomicGroupAsyncCommitsOnlyGroupFiles() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let trackedFile = repoURL.appendingPathComponent("feature.swift")
        let otherFile = repoURL.appendingPathComponent("other.swift")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try "base\n".write(to: otherFile, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        try "base\nfeature\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try "base\nother\n".write(to: otherFile, atomically: true, encoding: .utf8)

        let result = await gitManager.commitAtomicGroupAsync(
            files: ["feature.swift"],
            message: "feat: feature only"
        )
        if case let .failure(error) = result {
            XCTFail("Unexpected failure: \(error.localizedDescription)")
        }

        let status = try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertTrue(status.contains("other.swift"), "other.swift should remain uncommitted")

        let lastMessage = try runGit(["log", "-1", "--format=%s"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(lastMessage, "feat: feature only")
    }

    func testCommitAtomicGroupAsyncFailsOnEmptyFiles() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        let result = await gitManager.commitAtomicGroupAsync(files: [], message: "x")
        if case .success = result {
            XCTFail("Expected failure for empty files")
        }
    }

    func testPerformAtomicCommitsAsyncCreatesMultipleCommits() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let alphaFile = repoURL.appendingPathComponent("alpha.swift")
        let betaFile = repoURL.appendingPathComponent("beta.swift")
        try "base\n".write(to: alphaFile, atomically: true, encoding: .utf8)
        try "base\n".write(to: betaFile, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)

        try "base\nalpha\n".write(to: alphaFile, atomically: true, encoding: .utf8)
        try "base\nbeta\n".write(to: betaFile, atomically: true, encoding: .utf8)

        let groups = [
            AtomicCommitGroup(files: ["alpha.swift"], message: "feat: alpha"),
            AtomicCommitGroup(files: ["beta.swift"], message: "feat: beta")
        ]

        let result = await gitManager.performAtomicCommitsAsync(groups: groups)
        if case let .failure(error) = result {
            XCTFail("Unexpected failure: \(error.localizedDescription)")
        }

        let commitCount = try runGit(["rev-list", "--count", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(commitCount, "3")

        let remaining = try runGit(["status", "--porcelain"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(remaining.isEmpty, "Working tree should be clean after atomic commits")

        let messages = try runGit(["log", "-2", "--format=%s"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(messages.contains("feat: alpha"))
        XCTAssertTrue(messages.contains("feat: beta"))
    }

    func testPerformAtomicCommitsAsyncValidatesPlanBeforeCommitting() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let alphaFile = repoURL.appendingPathComponent("alpha.swift")
        try "base\n".write(to: alphaFile, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        try "base\nalpha\n".write(to: alphaFile, atomically: true, encoding: .utf8)

        let groups = [
            AtomicCommitGroup(files: ["alpha.swift"], message: "feat: alpha"),
            AtomicCommitGroup(files: [], message: "feat: empty causes failure")
        ]

        let result = await gitManager.performAtomicCommitsAsync(groups: groups)
        if case .success = result {
            XCTFail("Expected failure on empty second group")
        }

        let commitCount = try runGit(["rev-list", "--count", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(commitCount, "1", "Invalid atomic plans should fail before creating commits")
    }

    func testPerformAtomicCommitsAsyncRollsBackWhenLaterCommitFails() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let alphaFile = repoURL.appendingPathComponent("alpha.swift")
        let betaFile = repoURL.appendingPathComponent("beta.swift")
        try "base\n".write(to: alphaFile, atomically: true, encoding: .utf8)
        try "base\n".write(to: betaFile, atomically: true, encoding: .utf8)

        let hookURL = repoURL.appendingPathComponent(".git/hooks/pre-commit")
        try """
        #!/bin/sh
        counter=".git/hooks/atomic-counter"
        count=0
        if [ -f "$counter" ]; then
          count=$(cat "$counter")
        fi
        count=$((count + 1))
        echo "$count" > "$counter"
        if [ "$count" -ge 2 ]; then
          echo "stop second commit" >&2
          exit 1
        fi
        exit 0
        """.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookURL.path)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        try "base\nalpha\n".write(to: alphaFile, atomically: true, encoding: .utf8)
        try "base\nbeta\n".write(to: betaFile, atomically: true, encoding: .utf8)

        let groups = [
            AtomicCommitGroup(files: ["alpha.swift"], message: "feat: alpha"),
            AtomicCommitGroup(files: ["beta.swift"], message: "feat: beta")
        ]

        let result = await gitManager.performAtomicCommitsAsync(groups: groups)
        if case .success = result {
            XCTFail("Expected second commit to fail")
        }

        let commitCount = try runGit(["rev-list", "--count", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(commitCount, "1", "Atomic commit rollback should remove partial commits")

        let status = try runGit(["status", "--porcelain"], in: repoURL)
        XCTAssertTrue(status.contains("alpha.swift"))
        XCTAssertTrue(status.contains("beta.swift"))
    }
}
