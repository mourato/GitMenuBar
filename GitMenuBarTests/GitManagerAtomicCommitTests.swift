@testable import GitMenuBar
import XCTest

@MainActor
final class GitManagerAtomicCommitTests: XCTestCase {
    func testDiffForChangedFilesAsyncReturnsExpectedMap() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        let initialExpectation = expectation(description: "working tree refresh")
        gitManager.updateUncommittedFiles { initialExpectation.fulfill() }
        await fulfillment(of: [initialExpectation], timeout: 3)

        try "base\nchanged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let refreshExpectation = expectation(description: "working tree refresh after edit")
        gitManager.updateUncommittedFiles { refreshExpectation.fulfill() }
        await fulfillment(of: [refreshExpectation], timeout: 3)

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

    func testAtomicCommitPlanRejectsHunkThenWholeFileOverlap() {
        let hunk = AtomicCommitHunk(
            id: "feature.swift#hunk-1",
            path: "feature.swift",
            ordinal: 1,
            header: "@@ -1 +1 @@",
            additions: 1,
            removals: 1,
            patch: ""
        )
        let groups = [
            AtomicCommitGroup(files: [], hunks: [hunk.id], message: "feat: hunk"),
            AtomicCommitGroup(files: [hunk.path], message: "feat: whole file")
        ]

        XCTAssertThrowsError(
            try AtomicCommitPlan(
                groups: groups,
                allowedFiles: [hunk.path],
                hunksByID: [hunk.id: hunk]
            )
        ) { error in
            XCTAssertEqual(error as? AtomicCommitPlanValidationError, .fileHunkOverlap(hunk.path))
        }
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

    func testPerformHunkCommitsAsyncCreatesSeparateCommitsAndLeavesOmittedHunk() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("feature.swift")
        let baseLines = (1 ... 25).map { "line\($0)" }
        try (baseLines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "feature.swift"], in: repoURL)
        _ = try runGit(["commit", "-m", "base feature"], in: repoURL)
        let manager = GitManager(repositoryPathOverride: repoURL.path)
        var changedLines = baseLines
        changedLines[1] = "first"
        changedLines[11] = "second"
        changedLines[21] = "third"
        try (changedLines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        let initial = expectation(description: "refresh")
        manager.updateUncommittedFiles { initial.fulfill() }
        await fulfillment(of: [initial], timeout: 3)
        guard let snapshot = await manager.makeAtomicCommitSnapshotAsync(), snapshot.hunks.count == 3 else {
            return XCTFail("Expected three hunks in the snapshot")
        }
        let groups = [
            AtomicCommitGroup(files: [], hunks: [snapshot.hunks[0].id], message: "feat: first hunk"),
            AtomicCommitGroup(files: [], hunks: [snapshot.hunks[1].id], message: "feat: second hunk")
        ]
        let result = await manager.performHunkCommitsAsync(groups: groups, snapshot: snapshot)
        if case let .failure(error) = result {
            XCTFail(error.localizedDescription)
        }
        XCTAssertEqual(try runGit(["rev-list", "--count", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines), "4")
        XCTAssertTrue(try runGit(["status", "--porcelain"], in: repoURL).contains("feature.swift"))
    }

    func testPerformHunkCommitsAsyncRejectsStagedInput() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("feature.swift")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "base\nchanged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "feature.swift"], in: repoURL)
        let manager = GitManager(repositoryPathOverride: repoURL.path)
        let result = await manager.performHunkCommitsAsync(
            groups: [AtomicCommitGroup(files: ["feature.swift"], message: "feat: no")],
            snapshot: AtomicCommitSnapshot.fallback(for: [WorkingTreeFile(path: "feature.swift", lineDiff: .zero, status: .modified)])
        )
        if case .success = result {
            XCTFail("Expected staged-input rejection")
        }
        XCTAssertEqual(try runGit(["rev-list", "--count", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines), "1")
    }

    func testPerformHunkCommitsAsyncRollsBackWhenLaterCommitFails() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("feature.swift")
        let baseLines = (1 ... 25).map { "line\($0)" }
        try (baseLines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "feature.swift"], in: repoURL)
        _ = try runGit(["commit", "-m", "base feature"], in: repoURL)

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
          echo "stop second hunk commit" >&2
          exit 1
        fi
        exit 0
        """.write(to: hookURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookURL.path)

        var changedLines = baseLines
        changedLines[1] = "first"
        changedLines[11] = "second"
        changedLines[21] = "third"
        try (changedLines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = GitManager(repositoryPathOverride: repoURL.path)
        let refresh = expectation(description: "refresh")
        manager.updateUncommittedFiles { refresh.fulfill() }
        await fulfillment(of: [refresh], timeout: 3)
        guard let snapshot = await manager.makeAtomicCommitSnapshotAsync(), snapshot.hunks.count == 3 else {
            return XCTFail("Expected three hunks in the snapshot")
        }
        let groups = [
            AtomicCommitGroup(files: [], hunks: [snapshot.hunks[0].id], message: "feat: first hunk"),
            AtomicCommitGroup(files: [], hunks: [snapshot.hunks[1].id], message: "feat: second hunk")
        ]

        let result = await manager.performHunkCommitsAsync(groups: groups, snapshot: snapshot)
        if case .success = result {
            XCTFail("Expected later hunk commit failure")
        }
        XCTAssertEqual(
            try runGit(["rev-list", "--count", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines),
            "2"
        )
        XCTAssertTrue(try runGit(["status", "--porcelain"], in: repoURL).contains("feature.swift"))
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("first"))
        XCTAssertTrue(content.contains("second"))
        XCTAssertTrue(content.contains("third"))
    }

    func testPerformHunkCommitsAsyncRejectsChangedHeadAsStale() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("feature.swift")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "feature.swift"], in: repoURL)
        _ = try runGit(["commit", "-m", "base feature"], in: repoURL)
        try "base\nchanged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = GitManager(repositoryPathOverride: repoURL.path)
        let refresh = expectation(description: "refresh")
        manager.updateUncommittedFiles { refresh.fulfill() }
        await fulfillment(of: [refresh], timeout: 3)
        guard let snapshot = await manager.makeAtomicCommitSnapshotAsync(), let hunk = snapshot.hunks.first else {
            return XCTFail("Expected a snapshot hunk")
        }
        _ = try runGit(["commit", "--allow-empty", "-m", "move HEAD"], in: repoURL)

        let result = await manager.performHunkCommitsAsync(
            groups: [AtomicCommitGroup(files: [], hunks: [hunk.id], message: "feat: stale")],
            snapshot: snapshot
        )
        if case .success = result {
            XCTFail("Expected changed HEAD to invalidate the snapshot")
        }
        XCTAssertEqual(
            try runGit(["log", "-1", "--format=%s"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines),
            "move HEAD"
        )
    }
}
