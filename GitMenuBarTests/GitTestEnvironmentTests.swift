@testable import GitMenuBar
import XCTest

final class GitTestEnvironmentTests: XCTestCase {
    func testFixtureGitOperationsIgnoreHostileGlobalConfigAndRespectLocalRepoConfig() throws {
        let testDir = try makeTemporaryTestDirectory(testName: #function)
        let hostileConfigURL = testDir.appendingPathComponent("hostile.gitconfig")
        let hostileConfig = """
        [commit]
            gpgsign = true
        [gpg]
            program = /usr/bin/false
        """
        try hostileConfig.write(to: hostileConfigURL, atomically: true, encoding: .utf8)

        let repoURL = try createTemporaryGitRepository(testName: #function + "-repo")
        let testFile = repoURL.appendingPathComponent("work.txt")
        try "content\n".write(to: testFile, atomically: true, encoding: .utf8)
        try runGit(["add", "work.txt"], in: repoURL)

        // Negative control: unisolated execution forced to point to the hostile global config fails
        var unisolatedEnv = makeIsolatedGitEnvironment()
        unisolatedEnv["GIT_CONFIG_GLOBAL"] = hostileConfigURL.path
        XCTAssertThrowsError(
            try runGit(["commit", "-m", "unisolated fail"], in: repoURL, environment: unisolatedEnv),
            "Git commit should fail when forced to load hostile global signing configuration with a deliberately failing signing command"
        )

        // Positive control sanitizes the same hostile input before running Git.
        let isolatedEnv = makeIsolatedGitEnvironment(inheriting: unisolatedEnv)
        XCTAssertNoThrow(
            try runGit(["commit", "-m", "isolated success"], in: repoURL, environment: isolatedEnv)
        )

        // Verify local repository configuration remains functional and takes effect
        try runGit(["config", "test.fixture.key", "local-fixture-value"], in: repoURL)
        let configuredValue = try runGit(["config", "test.fixture.key"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(configuredValue, "local-fixture-value")

        // Verify local user configuration stored in the repository
        try runGit(["config", "user.name", "Local Config Name"], in: repoURL)
        let configuredName = try runGit(["config", "user.name"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(configuredName, "Local Config Name")
    }

    func testFixtureGitOperationsStripHostileInheritedEnvironmentVariables() throws {
        let testDir = try makeTemporaryTestDirectory(testName: #function)
        let hostileTemplateDir = testDir.appendingPathComponent("template")
        let hostileHooksDir = hostileTemplateDir.appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: hostileHooksDir, withIntermediateDirectories: true)

        let hostilePreCommit = hostileHooksDir.appendingPathComponent("pre-commit")
        let hookScript = """
        #!/bin/sh
        echo "Blocked by hostile template hook" >&2
        exit 1
        """
        try hookScript.write(to: hostilePreCommit, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostilePreCommit.path)

        var syntheticHostileEnv = ProcessInfo.processInfo.environment
        syntheticHostileEnv["GIT_DIR"] = "/nonexistent/fake/dir"
        syntheticHostileEnv["GIT_WORK_TREE"] = "/nonexistent/fake/worktree"
        syntheticHostileEnv["GIT_INDEX_FILE"] = "/nonexistent/fake/index"
        syntheticHostileEnv["GIT_OBJECT_DIRECTORY"] = "/nonexistent/fake/objects"
        syntheticHostileEnv["GIT_ALTERNATE_OBJECT_DIRECTORIES"] = "/nonexistent/fake/alt"
        syntheticHostileEnv["GIT_COMMON_DIR"] = "/nonexistent/fake/common"
        syntheticHostileEnv["GIT_TEMPLATE_DIR"] = hostileTemplateDir.path
        syntheticHostileEnv["GIT_CONFIG"] = "/nonexistent/fake/gitconfig"
        syntheticHostileEnv["GIT_CONFIG_PARAMETERS"] = "'commit.gpgsign=true'"
        syntheticHostileEnv["GIT_CONFIG_COUNT"] = "-1"
        syntheticHostileEnv["GIT_CONFIG_KEY_0"] = "commit.gpgsign"
        syntheticHostileEnv["GIT_CONFIG_VALUE_0"] = "true"
        syntheticHostileEnv["GIT_CONFIG_KEY_1"] = "core.hooksPath"
        syntheticHostileEnv["GIT_CONFIG_VALUE_1"] = "/nonexistent/hooks"

        let isolatedEnv = makeIsolatedGitEnvironment(inheriting: syntheticHostileEnv)

        let freshRepoDir = testDir.appendingPathComponent("fresh-repo")
        try FileManager.default.createDirectory(at: freshRepoDir, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], in: freshRepoDir, environment: isolatedEnv)

        // Verify hostile template hook was stripped and not installed
        let installedHook = freshRepoDir.appendingPathComponent(".git/hooks/pre-commit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedHook.path))

        let testFile = freshRepoDir.appendingPathComponent("test.txt")
        try "sample\n".write(to: testFile, atomically: true, encoding: .utf8)
        try runGit(["add", "test.txt"], in: freshRepoDir, environment: isolatedEnv)

        // Commit succeeds despite synthetic environment having commit.gpgsign and invalid path overrides
        XCTAssertNoThrow(
            try runGit(["commit", "-m", "isolated commit"], in: freshRepoDir, environment: isolatedEnv)
        )

        let logSubject = try runGit(["log", "-1", "--pretty=%s"], in: freshRepoDir, environment: isolatedEnv)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(logSubject, "isolated commit")
    }

    func testBareRemoteAndCloneTrackFixtureMainBranch() throws {
        let root = try makeTemporaryTestDirectory(testName: #function)
        let remote = root.appendingPathComponent("remote.git")
        let local = try createTemporaryGitRepository(testName: #function + "-local")
        try runGit(["init", "--bare", remote.path], in: root)
        XCTAssertEqual(
            try runGit(["symbolic-ref", "HEAD"], in: remote).trimmingCharacters(in: .whitespacesAndNewlines),
            "refs/heads/main"
        )
        try runGit(["remote", "add", "origin", remote.path], in: local)
        try runGit(["push", "-u", "origin", "HEAD"], in: local)
        let peer = root.appendingPathComponent("peer")
        try runGit(["clone", remote.path, peer.path], in: root)
        XCTAssertEqual(
            try runGit(["branch", "--show-current"], in: peer).trimmingCharacters(in: .whitespacesAndNewlines),
            "main"
        )
        XCTAssertEqual(
            try runGit(["rev-parse", "HEAD"], in: peer),
            try runGit(["rev-parse", "HEAD"], in: local)
        )
    }

    func testCreateTemporaryGitRepositoryInitializesDeterministicMainBranch() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(branch, "main")
    }
}
