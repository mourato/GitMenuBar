@testable import GitMenuBar
import XCTest

@MainActor
final class GitWorkingTreeServiceTests: XCTestCase {
    func testSingleFileStageAndUnstagePreservesOtherChangesAndFileContents() async throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        let other = try createTemporaryGitRepository(testName: #function + "-other")
        let service = GitWorkingTreeService(commandRunner: GitCommandRunner())
        let filename = "-file with spaces.txt"
        try "new\n".write(to: repository.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        try "changed\n".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "other\n".write(to: other.appendingPathComponent(filename), atomically: true, encoding: .utf8)

        try await service.stageFileAsync(path: filename, in: repository.path).get()
        XCTAssertEqual(try stagedPaths(in: repository), [filename])
        XCTAssertEqual(try stagedPaths(in: other), [])
        try await service.unstageFileAsync(path: filename, in: repository.path).get()
        XCTAssertEqual(try stagedPaths(in: repository), [])
        XCTAssertEqual(try String(contentsOf: repository.appendingPathComponent(filename), encoding: .utf8), "new\n")
        XCTAssertEqual(try String(contentsOf: repository.appendingPathComponent("README.md"), encoding: .utf8), "changed\n")
    }

    func testStageAndUnstageAllIncludesModifiedDeletedAndUntrackedFiles() async throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        let service = GitWorkingTreeService(commandRunner: GitCommandRunner())
        try "tracked\n".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repository)
        try runGit(["commit", "-m", "Add tracked file"], in: repository)
        try FileManager.default.removeItem(at: repository.appendingPathComponent("README.md"))
        try "modified\n".write(to: repository.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: repository.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        try await service.stageAllChangesAsync(in: repository.path).get()
        XCTAssertEqual(try stagedPaths(in: repository), ["README.md", "new.txt", "tracked.txt"])
        try await service.unstageAllChangesAsync(in: repository.path).get()
        XCTAssertEqual(try stagedPaths(in: repository), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent("README.md").path))
        XCTAssertEqual(try String(contentsOf: repository.appendingPathComponent("tracked.txt"), encoding: .utf8), "modified\n")
        XCTAssertEqual(try String(contentsOf: repository.appendingPathComponent("new.txt"), encoding: .utf8), "new\n")
    }

    func testAllOperationsRejectMissingAndInvalidRepositories() async throws {
        let directory = try makeTemporaryTestDirectory(testName: #function)
        let service = GitWorkingTreeService(commandRunner: GitCommandRunner())
        for path in ["", directory.appendingPathComponent("missing").path] {
            let results = await [
                service.stageFileAsync(path: "file.txt", in: path),
                service.stageAllChangesAsync(in: path),
                service.unstageFileAsync(path: "file.txt", in: path),
                service.unstageAllChangesAsync(in: path),
                service.discardFileChangesAsync(path: "file.txt", status: .modified, in: path),
                service.discardAllUnstagedChangesAsync(in: path)
            ]
            for result in results {
                guard case let .failure(error) = result else {
                    XCTFail("Expected failure for repository '\(path)'")
                    continue
                }
                XCTAssertTrue(error is GitOperationError)
            }
        }
    }

    func testDiscardTrackedAndStagedChangesRestoresHeadAndLeavesOtherRepositoryUntouched() async throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        let other = try createTemporaryGitRepository(testName: #function + "-other")
        let service = GitWorkingTreeService(commandRunner: GitCommandRunner())
        let file = repository.appendingPathComponent("README.md")
        let original = try String(contentsOf: file, encoding: .utf8)
        for staged in [false, true] {
            try "changed\n".write(to: file, atomically: true, encoding: .utf8)
            try "other\n".write(to: other.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            if staged {
                try runGit(["add", "README.md"], in: repository)
            }
            try await service.discardFileChangesAsync(path: "README.md", status: .modified, in: repository.path).get()
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original)
            XCTAssertEqual(try stagedPaths(in: repository), [])
            XCTAssertEqual(try String(contentsOf: other.appendingPathComponent("README.md"), encoding: .utf8), "other\n")
        }
    }

    func testDiscardUntrackedAndNewStagedFilesRemovesThemOnDisk() async throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        let service = GitWorkingTreeService(commandRunner: GitCommandRunner())
        for staged in [false, true] {
            let filename = "new file.txt"
            let file = repository.appendingPathComponent(filename)
            try "new\n".write(to: file, atomically: true, encoding: .utf8)
            if staged {
                try runGit(["add", "--", filename], in: repository)
            }
            try await service.discardFileChangesAsync(path: filename, status: staged ? .modified : .untracked, in: repository.path).get()
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertEqual(try stagedPaths(in: repository), [])
        }
    }

    func testDiscardAllUnstagedPreservesIndexAndIgnoredFiles() async throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        let service = GitWorkingTreeService(commandRunner: GitCommandRunner())
        let file = repository.appendingPathComponent("README.md")
        try "staged\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repository)
        try "unstaged\n".write(to: file, atomically: true, encoding: .utf8)
        try "new\n".write(to: repository.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try "ignored.txt\n".write(to: repository.appendingPathComponent(".git/info/exclude"), atomically: true, encoding: .utf8)
        try "ignored\n".write(to: repository.appendingPathComponent("ignored.txt"), atomically: true, encoding: .utf8)
        try await service.discardAllUnstagedChangesAsync(in: repository.path).get()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "staged\n")
        XCTAssertEqual(try stagedPaths(in: repository), ["README.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appendingPathComponent("new.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.appendingPathComponent("ignored.txt").path))
    }

    func testDiffOutputsIncludeStagedTrackedAndUntrackedChanges() async throws {
        let repository = try createTemporaryGitRepository(testName: #function)
        let service = GitWorkingTreeService(commandRunner: GitCommandRunner())
        XCTAssertFalse(service.hasUncommittedChanges(in: repository.path))
        let initiallyChanged = await service.hasUncommittedChangesAsync(in: repository.path)
        XCTAssertFalse(initiallyChanged)
        try "staged marker\n".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repository)
        try "unstaged marker\n".write(to: repository.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "untracked marker\n".write(to: repository.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let staged = service.diffStaged(in: repository.path)
        let unstaged = service.diffUnstaged(in: repository.path)
        XCTAssertTrue(staged.contains("+staged marker"))
        XCTAssertFalse(staged.contains("untracked marker"))
        XCTAssertTrue(unstaged.contains("+unstaged marker"))
        XCTAssertTrue(unstaged.contains("+untracked marker"))
        XCTAssertTrue(unstaged.contains("new file mode"))
        XCTAssertEqual(service.diffAll(in: repository.path), [staged, unstaged].joined(separator: "\n\n"))
        let asyncStaged = await service.diffStagedAsync(in: repository.path)
        let asyncUnstaged = await service.diffUnstagedAsync(in: repository.path)
        let asyncAll = await service.diffAllAsync(in: repository.path)
        XCTAssertEqual(asyncStaged, staged)
        XCTAssertEqual(asyncUnstaged, unstaged)
        XCTAssertEqual(asyncAll, [staged, unstaged].joined(separator: "\n\n"))
        XCTAssertTrue(service.hasUncommittedChanges(in: repository.path))
        let changed = await service.hasUncommittedChangesAsync(in: repository.path)
        XCTAssertTrue(changed)
    }

    private func stagedPaths(in repository: URL) throws -> [String] {
        try runGit(["diff", "--cached", "--name-only", "--no-renames"], in: repository)
            .split(separator: "\n").map(String.init).sorted()
    }
}
