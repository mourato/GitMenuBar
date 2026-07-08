@testable import GitMenuBar
import XCTest

private struct StubGroupingAI: AtomicGroupingAIProviding {
    var response: String
    var shouldThrow = false

    func generateRawResponse(
        prompt _: String,
        provider _: AIProviderConfig,
        apiKey _: String,
        model _: String
    ) async throws -> String {
        if shouldThrow {
            throw NSError(domain: "StubGroupingAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "stub failure"])
        }
        return response
    }
}

final class AICommitGrouperServiceTests: XCTestCase {
    private var dummyProvider: AIProviderConfig {
        AIProviderConfig(
            name: "stub",
            type: .openAI,
            endpointURL: "https://example.com/v1",
            selectedModel: "model-x"
        )
    }

    private func sampleFiles() -> [WorkingTreeFile] {
        [
            WorkingTreeFile(path: "Sources/Feature/api.swift", lineDiff: .zero, status: .modified),
            WorkingTreeFile(path: "Sources/Utils/helper.swift", lineDiff: .zero, status: .modified),
            WorkingTreeFile(path: "Docs/guide.md", lineDiff: .zero, status: .modified)
        ]
    }

    func testBuildGroupingPromptIncludesFileNamesAndDiffs() {
        let stub = StubGroupingAI(response: "")
        let service = AICommitGrouperService(aiService: stub)
        let files = sampleFiles()
        let diffs = [
            "Sources/Feature/api.swift": "+func newAPI()",
            "Sources/Utils/helper.swift": "+func helper()",
            "Docs/guide.md": "+# Guide"
        ]

        let prompt = service.buildGroupingPrompt(changedFiles: files, diffPerFile: diffs)

        XCTAssertTrue(prompt.contains("Sources/Feature/api.swift"))
        XCTAssertTrue(prompt.contains("Sources/Utils/helper.swift"))
        XCTAssertTrue(prompt.contains("Docs/guide.md"))
        XCTAssertTrue(prompt.contains("+func newAPI()"))
        XCTAssertTrue(prompt.contains("JSON array"))
    }

    func testParseGroupsFromResponseValidJSON() throws {
        let stub = StubGroupingAI(response: "")
        let service = AICommitGrouperService(aiService: stub)
        let json = """
        [
          {"files": ["a.swift"], "message": "feat: a"},
          {"files": ["b.swift", "c.swift"], "message": "fix: b and c"}
        ]
        """
        let groups = try service.parseGroupsFromResponse(json)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].files, ["a.swift"])
        XCTAssertEqual(groups[0].message, "feat: a")
        XCTAssertEqual(groups[1].files, ["b.swift", "c.swift"])
    }

    func testParseGroupsFromResponseStripsCodeFences() throws {
        let stub = StubGroupingAI(response: "")
        let service = AICommitGrouperService(aiService: stub)
        let json = """
        ```json
        [{"files": ["x.swift"], "message": "chore: x"}]
        ```
        """
        let groups = try service.parseGroupsFromResponse(json)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files, ["x.swift"])
    }

    func testParseGroupsFromResponseInvalidJSONThrows() {
        let stub = StubGroupingAI(response: "")
        let service = AICommitGrouperService(aiService: stub)
        XCTAssertThrowsError(try service.parseGroupsFromResponse("not json at all"))
    }

    func testParseGroupsFromResponseDropsEmptyGroups() throws {
        let stub = StubGroupingAI(response: "")
        let service = AICommitGrouperService(aiService: stub)
        let json = """
        [
          {"files": [], "message": "empty"},
          {"files": ["real.swift"], "message": "feat: real"}
        ]
        """
        let groups = try service.parseGroupsFromResponse(json)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files, ["real.swift"])
    }

    func testGenerateAtomicGroupsUsesAIGroupsWhenAvailable() async throws {
        let stub = StubGroupingAI(response: """
        [{"files": ["Sources/Feature/api.swift"], "message": "feat: api"}]
        """)
        let service = AICommitGrouperService(aiService: stub)
        let groups = try await service.generateAtomicGroups(
            changedFiles: sampleFiles(),
            diffPerFile: [:],
            provider: dummyProvider,
            apiKey: "key",
            model: "model"
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].message, "feat: api")
    }

    func testGenerateAtomicGroupsFallsBackWhenAIThrows() async throws {
        let stub = StubGroupingAI(response: "", shouldThrow: true)
        let service = AICommitGrouperService(aiService: stub)
        let groups = try await service.generateAtomicGroups(
            changedFiles: sampleFiles(),
            diffPerFile: [:],
            provider: dummyProvider,
            apiKey: "key",
            model: "model"
        )
        XCTAssertEqual(groups.count, 3)
        XCTAssertTrue(groups.allSatisfy { $0.files.count == 1 })
    }

    func testGenerateAtomicGroupsFallsBackOnInvalidJSON() async throws {
        let stub = StubGroupingAI(response: "totally not json")
        let service = AICommitGrouperService(aiService: stub)
        let groups = try await service.generateAtomicGroups(
            changedFiles: sampleFiles(),
            diffPerFile: [:],
            provider: dummyProvider,
            apiKey: "key",
            model: "model"
        )
        XCTAssertEqual(groups.count, 3)
    }

    func testMoveFileStaticHelper() {
        var source = AtomicCommitGroup(files: ["a.swift", "b.swift"], message: "m")
        var target = AtomicCommitGroup(files: ["c.swift"], message: "m")
        AICommitGrouperService.moveFile("b.swift", from: &source, to: &target)
        XCTAssertEqual(source.files, ["a.swift"])
        XCTAssertEqual(target.files, ["c.swift", "b.swift"])
    }

    func testAtomicCommitGroupModel() {
        var group = AtomicCommitGroup(files: ["a", "b"], message: "feat: x")
        XCTAssertEqual(group.fileCount, 2)
        XCTAssertEqual(group.id, group.id)
        group.files = ["a"]
        XCTAssertEqual(group.fileCount, 1)
    }
}
