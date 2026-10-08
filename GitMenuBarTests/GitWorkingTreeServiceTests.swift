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
                service.unstageAllChangesAsync(in: path)
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

    private func stagedPaths(in repository: URL) throws -> [String] {
        try runGit(["diff", "--cached", "--name-only", "--no-renames"], in: repository)
            .split(separator: "\n").map(String.init).sorted()
    }
}
