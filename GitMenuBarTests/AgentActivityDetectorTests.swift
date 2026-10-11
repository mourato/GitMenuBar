@testable import GitMenuBar
import SQLite3
import XCTest

final class AgentActivityDetectorTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let uniqueName = "AgentActivityDetectorTests_\(UUID().uuidString)"
        temporaryDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir = temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: dir)
        }
        try super.tearDownWithError()
    }

    func testClaudeInstallPathsAndCursorAgentOnly() {
        XCTAssertEqual(AgentActivityDetector.harness(
            forProcessName: "node", binaryPath: "/opt/homebrew/bin/node",
            arguments: ["node", "/opt/lib/node_modules/@anthropic-ai/claude-code/cli.js", "--resume"]
        ), .claudeCode)
        XCTAssertEqual(AgentActivityDetector.harness(
            forProcessName: "2.1.0", binaryPath: "/Users/test/.local/share/claude/versions/2.1.0"
        ), .claudeCode)
        XCTAssertNil(AgentActivityDetector.harness(
            forProcessName: "node", binaryPath: "/opt/homebrew/bin/node", arguments: ["node", "server.js"]
        ))
        XCTAssertEqual(AgentActivityDetector.harness(forProcessName: "cursor-agent", binaryPath: "/bin/cursor-agent"), .cursor)
        for name in ["Cursor", "Cursor Helper", "cursor", "cursor-server"] {
            XCTAssertNil(AgentActivityDetector.harness(forProcessName: name, binaryPath: "/bin/" + name))
        }
    }

    // MARK: - Path Normalization & Matching Tests

    func testPathNormalization() {
        XCTAssertEqual(AgentActivityDetector.normalizePath(""), "")
        XCTAssertEqual(AgentActivityDetector.normalizePath("/Users/user/project/"), "/Users/user/project")
        XCTAssertEqual(AgentActivityDetector.normalizePath("/Users/user/project"), "/Users/user/project")

        // Resolves symlinks (e.g. /var -> /private/var on macOS)
        let resolvedTmp = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().standardized.path
        XCTAssertEqual(AgentActivityDetector.normalizePath("/tmp"), resolvedTmp)
    }

    func testPathMatching() {
        let project = "/Users/test/workspace/repo"

        // Exact match
        XCTAssertTrue(AgentActivityDetector.isMatchingPath(processCwd: project, projectPath: project))
        XCTAssertTrue(AgentActivityDetector.isMatchingPath(processCwd: project + "/", projectPath: project))

        // Subdirectory match
        XCTAssertTrue(AgentActivityDetector.isMatchingPath(processCwd: project + "/Sources/Core", projectPath: project))
        XCTAssertTrue(AgentActivityDetector.isMatchingPath(processCwd: project + "/Deep/Nested/Dir", projectPath: project))

        // Non-matching sibling directory (prefix overlap without slash boundary)
        XCTAssertFalse(AgentActivityDetector.isMatchingPath(processCwd: project + "-other", projectPath: project))
        XCTAssertFalse(AgentActivityDetector.isMatchingPath(processCwd: project + "_backup", projectPath: project))

        // Parent or completely different path
        XCTAssertFalse(AgentActivityDetector.isMatchingPath(processCwd: "/Users/test/workspace", projectPath: project))
        XCTAssertFalse(AgentActivityDetector.isMatchingPath(processCwd: "/Users/test/other", projectPath: project))
        XCTAssertFalse(AgentActivityDetector.isMatchingPath(processCwd: "", projectPath: project))
        XCTAssertFalse(AgentActivityDetector.isMatchingPath(processCwd: project, projectPath: ""))
    }

    // MARK: - Process Harness Identification Tests

    func testHarnessIdentification() {
        // Claude Code
        XCTAssertEqual(
            AgentActivityDetector.harness(forProcessName: "claude", binaryPath: "/usr/local/bin/claude"),
            .claudeCode
        )
        XCTAssertEqual(
            AgentActivityDetector.harness(forProcessName: "claude-code", binaryPath: "/opt/homebrew/bin/claude-code"),
            .claudeCode
        )

        // Codex
        XCTAssertEqual(
            AgentActivityDetector.harness(forProcessName: "codex", binaryPath: "/usr/local/bin/codex"),
            .codex
        )
        XCTAssertEqual(
            AgentActivityDetector.harness(forProcessName: "codex-app-server", binaryPath: "/Applications/Codex.app/Contents/MacOS/codex-app-server"),
            .codex
        )

        // OpenCode
        XCTAssertEqual(
            AgentActivityDetector.harness(forProcessName: "opencode", binaryPath: "/opt/homebrew/bin/opencode"),
            .opencode
        )

        // Cursor IDE and helpers are not agent processes.
        XCTAssertNil(AgentActivityDetector.harness(forProcessName: "Cursor", binaryPath: "/Applications/Cursor.app/Contents/MacOS/Cursor"))
        XCTAssertNil(AgentActivityDetector.harness(forProcessName: "cursor", binaryPath: "/usr/local/bin/cursor"))
        XCTAssertNil(AgentActivityDetector.harness(forProcessName: "Cursor Helper", binaryPath: ""))

        // Antigravity
        XCTAssertEqual(
            AgentActivityDetector.harness(forProcessName: "agy_acp_server.par", binaryPath: "/path/agy_acp_server.par"),
            .antigravity
        )
        XCTAssertEqual(
            AgentActivityDetector.harness(forProcessName: "localharness_external", binaryPath: "/path/localharness_external"),
            .antigravity
        )

        // Non-agent processes
        XCTAssertNil(AgentActivityDetector.harness(forProcessName: "git", binaryPath: "/usr/bin/git"))
        XCTAssertNil(AgentActivityDetector.harness(forProcessName: "zsh", binaryPath: "/bin/zsh"))
        XCTAssertNil(AgentActivityDetector.harness(forProcessName: "Safari", binaryPath: "/Applications/Safari.app/Contents/MacOS/Safari"))
    }

    func testCandidateAgentProcessFilter() {
        XCTAssertTrue(AgentActivityDetector.isCandidateAgentProcess(name: "claude", binaryPath: ""))
        XCTAssertTrue(AgentActivityDetector.isCandidateAgentProcess(name: "codex", binaryPath: ""))
        XCTAssertTrue(AgentActivityDetector.isCandidateAgentProcess(name: "opencode", binaryPath: ""))
        XCTAssertFalse(AgentActivityDetector.isCandidateAgentProcess(name: "Cursor", binaryPath: ""))
        XCTAssertTrue(AgentActivityDetector.isCandidateAgentProcess(name: "agy_acp_server", binaryPath: ""))
        XCTAssertTrue(AgentActivityDetector.isCandidateAgentProcess(name: "localharness_external", binaryPath: ""))
        XCTAssertFalse(AgentActivityDetector.isCandidateAgentProcess(name: "bash", binaryPath: "/bin/bash"))
    }

    // MARK: - Candidate Slugs Tests

    func testCandidateSlugs() {
        let path = "/Users/test/workspace/myproject"
        let slugs = AgentActivityDetector.candidateSlugs(for: path)

        XCTAssertTrue(slugs.contains("-Users-test-workspace-myproject"))
        XCTAssertTrue(slugs.contains("Users-test-workspace-myproject"))

        let dotPath = "/Users/test/.agents"
        let dotSlugs = AgentActivityDetector.candidateSlugs(for: dotPath)
        XCTAssertTrue(dotSlugs.contains("-Users-test--agents"))
    }

    // MARK: - Process Detection & Deduplication Tests

    func testProcessDetectionMatchesProjectCwd() async {
        let projectPath = "/Users/test/workspace/repoA"

        let mockProcessQuerier = MockAgentProcessQuerier(processes: [
            RunningAgentProcess(pid: 101, name: "claude", binaryPath: "/bin/claude", cwd: projectPath),
            RunningAgentProcess(pid: 102, name: "agy_acp_server", binaryPath: "/bin/agy_acp_server", cwd: projectPath + "/Sources"),
            RunningAgentProcess(pid: 103, name: "localharness_external", binaryPath: "/bin/localharness_external", cwd: projectPath),
            RunningAgentProcess(pid: 104, name: "codex", binaryPath: "/bin/codex", cwd: "/Users/test/workspace/repoB")
        ])

        let mockSessionQuerier = MockAgentSessionQuerier()

        let detector = AgentActivityDetector(
            processQuerier: mockProcessQuerier,
            sessionQuerier: mockSessionQuerier
        )

        let activities = await detector.detectAgents(for: [projectPath])
        let repoActivities = activities[projectPath] ?? []

        XCTAssertEqual(repoActivities.count, 2)

        let harnesses = repoActivities.map(\.harness)
        XCTAssertTrue(harnesses.contains(.claudeCode))
        XCTAssertTrue(harnesses.contains(.antigravity))
        XCTAssertFalse(harnesses.contains(.codex))

        for activity in repoActivities {
            XCTAssertEqual(activity.status, .running)
        }
    }

    // MARK: - Priority Tests: Running Over Recent

    func testPriorityRunningOverRecent() async {
        let projectPath = "/Users/test/workspace/repoA"
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let thirtyMinutesAgo = fixedNow.addingTimeInterval(-1800)

        let mockProcessQuerier = MockAgentProcessQuerier(processes: [
            RunningAgentProcess(pid: 201, name: "claude", binaryPath: "/bin/claude", cwd: projectPath)
        ])

        let mockSessionQuerier = MockAgentSessionQuerier(sessions: [
            projectPath: [
                AgentProjectActivity(harness: .claudeCode, status: .recent(thirtyMinutesAgo)),
                AgentProjectActivity(harness: .codex, status: .recent(thirtyMinutesAgo))
            ]
        ])

        let detector = AgentActivityDetector(
            processQuerier: mockProcessQuerier,
            sessionQuerier: mockSessionQuerier,
            nowProvider: { fixedNow }
        )

        let results = await detector.detectAgents(for: [projectPath])
        let activities = results[projectPath] ?? []

        XCTAssertEqual(activities.count, 2)

        let claudeActivity = activities.first { $0.harness == .claudeCode }
        let codexActivity = activities.first { $0.harness == .codex }

        XCTAssertEqual(claudeActivity?.status, .running)
        XCTAssertEqual(codexActivity?.status, .recent(thirtyMinutesAgo))
    }

    func testCodexAppServersDoNotAttributeLaunchDirectoryAsRunning() async {
        let path = "/tmp/server-launch"
        let processes = MockAgentProcessQuerier(processes: [
            RunningAgentProcess(pid: 1, name: "codex-app-server", binaryPath: "/bin/codex-app-server", cwd: path),
            RunningAgentProcess(pid: 2, name: "codex", binaryPath: "/bin/codex", cwd: path, arguments: ["codex", "app-server"])
        ])
        let detector = AgentActivityDetector(processQuerier: processes, sessionQuerier: MockAgentSessionQuerier())
        let results = await detector.detectAgents(for: [path])
        XCTAssertEqual(results[path], [])
    }

    func testEachCycleQueriesFreshActivity() async {
        let processes = MockAgentProcessQuerier()
        let detector = AgentActivityDetector(processQuerier: processes, sessionQuerier: MockAgentSessionQuerier())
        _ = await detector.detectAgents(for: ["/tmp/project"])
        _ = await detector.detectAgents(for: ["/tmp/project"])
        let count = await processes.queryCount
        XCTAssertEqual(count, 2)
    }
}

// MARK: - Test Doubles

actor MockAgentProcessQuerier: AgentProcessQuerying {
    private let processes: [RunningAgentProcess]
    private(set) var queryCount: Int = 0

    init(processes: [RunningAgentProcess] = []) {
        self.processes = processes
    }

    // swiftlint:disable:next async_without_await
    func runningProcesses() async -> [RunningAgentProcess] {
        queryCount += 1
        return processes
    }
}

actor MockAgentSessionQuerier: AgentSessionQuerying {
    private let sessions: [String: [AgentProjectActivity]]
    private(set) var queryCount: Int = 0

    init(sessions: [String: [AgentProjectActivity]] = [:]) {
        self.sessions = sessions
    }

    // swiftlint:disable:next async_without_await
    func recentActivities(for _: [String], now _: Date) async -> [String: [AgentProjectActivity]] {
        queryCount += 1
        return sessions
    }
}
