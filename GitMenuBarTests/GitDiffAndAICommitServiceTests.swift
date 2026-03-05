@testable import GitMenuBar
import XCTest

final class GitDiffAndAICommitServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testDiffScopeStagedOnly() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        try "base\nstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoURL)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        let staged = gitManager.diffStaged()
        let unstaged = gitManager.diffUnstaged()

        XCTAssertTrue(staged.contains("+staged"))
        XCTAssertFalse(unstaged.contains("+staged"))
    }

    func testDiffScopeUnstagedOnly() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")

        try "base\nunstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        let staged = gitManager.diffStaged()
        let unstaged = gitManager.diffUnstaged()

        XCTAssertTrue(staged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(unstaged.contains("+unstaged"))
    }

    func testDiffScopeMixedAndUntrackedIncludedInAll() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let trackedFile = repoURL.appendingPathComponent("README.md")
        let untrackedFile = repoURL.appendingPathComponent("NEW_FILE.md")

        try "base\nstaged\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: repoURL)

        try "base\nstaged\nunstaged\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try "untracked content\n".write(to: untrackedFile, atomically: true, encoding: .utf8)

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        let all = gitManager.diffAll()

        XCTAssertTrue(all.contains("+staged"))
        XCTAssertTrue(all.contains("+unstaged"))
        XCTAssertTrue(all.contains("NEW_FILE.md"))
    }

    func testServiceFallsBackToAllWhenDefaultScopeIsStagedAndNoStagedDiff() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        try "base\nonly-unstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let session = makeMockedURLSession()
        let service = AICommitMessageService(maxDiffCharacters: 10000, session: session)

        var capturedPrompt = ""

        MockURLProtocol.requestHandler = { request in
            let body = self.requestBodyData(from: request)
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                let messages = json["messages"] as? [[String: Any]]
                let userMessage = messages?.first(where: { ($0["role"] as? String) == "user" })
                capturedPrompt = userMessage?["content"] as? String ?? ""
            }

            let response = "{\"choices\":[{\"message\":{\"content\":\"feat: generated\"}}]}"
            let data = response.data(using: .utf8) ?? Data()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let provider = AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://mock.openai.local",
            selectedModel: "gpt-4.1"
        )

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        let generated = try await service.generateCommitMessage(
            provider: provider,
            apiKey: "test-key",
            model: "gpt-4.1",
            preferredScopeMode: .stagedWithFallbackAll,
            overrideScope: nil,
            gitManager: gitManager
        )

        XCTAssertEqual(generated, "feat: generated")
        XCTAssertTrue(capturedPrompt.contains("Diff scope used: All."))
    }

    func testServiceAppliesDeterministicDiffTruncationNotice() async throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let fileURL = repoURL.appendingPathComponent("README.md")
        let longBody = String(repeating: "line-with-content\n", count: 300)
        try ("base\n" + longBody).write(to: fileURL, atomically: true, encoding: .utf8)

        let session = makeMockedURLSession()
        let service = AICommitMessageService(maxDiffCharacters: 100, session: session)

        var capturedPrompt = ""

        MockURLProtocol.requestHandler = { request in
            let body = self.requestBodyData(from: request)
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                let messages = json["messages"] as? [[String: Any]]
                let userMessage = messages?.first(where: { ($0["role"] as? String) == "user" })
                capturedPrompt = userMessage?["content"] as? String ?? ""
            }

            let response = "{\"choices\":[{\"message\":{\"content\":\"fix: generated\"}}]}"
            let data = response.data(using: .utf8) ?? Data()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let provider = AIProviderConfig(
            name: "OpenAI",
            type: .openAI,
            endpointURL: "https://mock.openai.local",
            selectedModel: "gpt-4.1"
        )

        let gitManager = GitManager(repositoryPathOverride: repoURL.path)
        _ = try await service.generateCommitMessage(
            provider: provider,
            apiKey: "test-key",
            model: "gpt-4.1",
            preferredScopeMode: .stagedWithFallbackAll,
            overrideScope: .all,
            gitManager: gitManager
        )

        XCTAssertTrue(capturedPrompt.contains("Diff truncated to 100 characters"))
    }

    private func requestBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let bodyStream = request.httpBodyStream else {
            return Data()
        }

        bodyStream.open()
        defer { bodyStream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while bodyStream.hasBytesAvailable {
            let bytesRead = bodyStream.read(&buffer, maxLength: bufferSize)
            if bytesRead <= 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        return data
    }
}
