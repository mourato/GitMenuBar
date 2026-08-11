@testable import GitMenuBar
import XCTest

private struct StubGroupingAI: AtomicGroupingAIProviding {
    var response: String
    var shouldThrow = false

    // swiftlint:disable async_without_await
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
    // swiftlint:enable async_without_await
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

    func testGenerateAtomicGroupsThrowsOnPollutedOnlyGroupMessage() async {
        let stub = StubGroupingAI(response: """
        [{"files": ["Sources/Feature/api.swift"], "message": "Generated by Cursor"}]
        """)
        let service = AICommitGrouperService(aiService: stub)

        do {
            _ = try await service.generateAtomicGroups(
                changedFiles: sampleFiles(),
                diffPerFile: [:],
                provider: dummyProvider,
                apiKey: "key",
                model: "model"
            )
            XCTFail("Expected Message policy rejection")
        } catch let error as AIError {
            guard case .messagePolicyRejected = error else {
                return XCTFail("Unexpected AIError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateAtomicGroupsStripsPollutionAndKeepsSubject() async throws {
        let stub = StubGroupingAI(response: """
        [{"files": ["Sources/Feature/api.swift"], "message": "feat: api\\n\\nGenerated by Cursor"}]
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

    func testHunkResponseAllowsDifferentHunksFromOneFile() throws {
        let file = WorkingTreeFile(path: "a.swift", lineDiff: .zero, status: .modified)
        let hunk1 = AtomicCommitHunk(id: "a.swift#hunk-1", path: "a.swift", ordinal: 1, header: "@@ -1 +1 @@", additions: 1, removals: 1, patch: "")
        let hunk2 = AtomicCommitHunk(id: "a.swift#hunk-2", path: "a.swift", ordinal: 2, header: "@@ -4 +4 @@", additions: 1, removals: 1, patch: "")
        let snapshot = AtomicCommitSnapshot(fingerprint: "x", files: [file], hunks: [hunk1, hunk2])
        let service = AICommitGrouperService(aiService: StubGroupingAI(response: ""))
        let groups = try service.parseHunkGroupsFromResponse("""
        [{"hunks":["a.swift#hunk-1"],"message":"fix: first"},{"hunks":["a.swift#hunk-2"],"message":"fix: second"}]
        """, snapshot: snapshot)
        XCTAssertEqual(groups.map(\.hunks), [["a.swift#hunk-1"], ["a.swift#hunk-2"]])
    }

    func testHunkResponseRejectsDuplicateAndUnknownReferences() {
        let file = WorkingTreeFile(path: "a.swift", lineDiff: .zero, status: .modified)
        let hunk = AtomicCommitHunk(id: "a.swift#hunk-1", path: "a.swift", ordinal: 1, header: "@@", additions: 1, removals: 0, patch: "")
        let snapshot = AtomicCommitSnapshot(fingerprint: "x", files: [file], hunks: [hunk])
        let service = AICommitGrouperService(aiService: StubGroupingAI(response: ""))
        XCTAssertThrowsError(try service.parseHunkGroupsFromResponse("""
        [{"hunks":["a.swift#hunk-1"],"message":"fix: a"},{"hunks":["a.swift#hunk-1"],"message":"fix: b"}]
        """, snapshot: snapshot))
        XCTAssertThrowsError(try service.parseHunkGroupsFromResponse("""
        [{"hunks":["a.swift#hunk-9"],"message":"fix: a"}]
        """, snapshot: snapshot))
    }

    func testHunkGroupingPromptIncludesDistinctPatchContentAndMetadata() {
        let file = WorkingTreeFile(path: "a.swift", lineDiff: .zero, status: .modified)
        let hunks = [
            AtomicCommitHunk(id: "a.swift#hunk-1", path: "a.swift", ordinal: 1, header: "@@ -1 +1 @@", additions: 1, removals: 1, patch: "-oldOne\n+newOne"),
            AtomicCommitHunk(id: "a.swift#hunk-2", path: "a.swift", ordinal: 2, header: "@@ -4 +4 @@", additions: 1, removals: 1, patch: "-oldTwo\n+newTwo")
        ]
        let snapshot = AtomicCommitSnapshot(fingerprint: "x", files: [file], hunks: hunks)
        let prompt = AICommitGrouperService(aiService: StubGroupingAI(response: ""))
            .buildHunkGroupingPrompt(snapshot: snapshot)

        XCTAssertTrue(prompt.contains("a.swift#hunk-1"))
        XCTAssertTrue(prompt.contains("@@ -1 +1 @@"))
        XCTAssertTrue(prompt.contains("+newOne"))
        XCTAssertTrue(prompt.contains("a.swift#hunk-2"))
        XCTAssertTrue(prompt.contains("@@ -4 +4 @@"))
        XCTAssertTrue(prompt.contains("+newTwo"))
    }

    func testHunkGroupingPromptIncludesCompleteSmallPatchAndEmptyPatchMetadata() {
        let files = [
            WorkingTreeFile(path: "a.swift", lineDiff: .zero, status: .modified),
            WorkingTreeFile(path: "b.swift", lineDiff: .zero, status: .modified)
        ]
        let hunks = [
            AtomicCommitHunk(id: "a.swift#hunk-1", path: "a.swift", ordinal: 1, header: "@@", additions: 1, removals: 0, patch: "+line"),
            AtomicCommitHunk(id: "b.swift#hunk-1", path: "b.swift", ordinal: 1, header: "@@", additions: 0, removals: 0, patch: "")
        ]
        let snapshot = AtomicCommitSnapshot(fingerprint: "x", files: files, hunks: hunks)
        let prompt = AICommitGrouperService(aiService: StubGroupingAI(response: ""))
            .buildHunkGroupingPrompt(snapshot: snapshot)

        XCTAssertTrue(prompt.contains("PATCH: (empty)"))
        XCTAssertTrue(prompt.contains("PATCH \(hunks[0].id)"))
        XCTAssertTrue(prompt.contains("+line"))
        XCTAssertTrue(prompt.contains("b.swift#hunk-1: b.swift"))
    }

    func testHunkGroupingPromptBoundsOversizedPatchesAndMarksTruncation() {
        let file = WorkingTreeFile(path: "a.swift", lineDiff: .zero, status: .modified)
        let patch = String(repeating: "+distinct-line\n", count: 10000)
        let hunk = AtomicCommitHunk(id: "a.swift#hunk-1", path: "a.swift", ordinal: 1, header: "@@", additions: 10000, removals: 0, patch: patch)
        let snapshot = AtomicCommitSnapshot(fingerprint: "x", files: [file], hunks: [hunk])
        let prompt = AICommitGrouperService(aiService: StubGroupingAI(response: ""))
            .buildHunkGroupingPrompt(snapshot: snapshot)

        XCTAssertLessThanOrEqual(prompt.count, 40000)
        XCTAssertTrue(prompt.contains("truncated; omitted"))
        XCTAssertTrue(prompt.contains("a.swift#hunk-1: a.swift"))
    }

    func testHunkGroupingPromptBoundsExtremeHunkMetadata() {
        let file = WorkingTreeFile(path: "a.swift", lineDiff: .zero, status: .modified)
        let hunks = (1 ... 10000).map { index in
            AtomicCommitHunk(id: "a.swift#hunk-\(index)", path: "a.swift", ordinal: index, header: "@@", additions: 0, removals: 0, patch: "")
        }
        let snapshot = AtomicCommitSnapshot(fingerprint: "x", files: [file], hunks: hunks)
        let prompt = AICommitGrouperService(aiService: StubGroupingAI(response: ""))
            .buildHunkGroupingPrompt(snapshot: snapshot)

        XCTAssertLessThanOrEqual(prompt.count, 40000, "prompt count: \(prompt.count)")
        XCTAssertTrue(prompt.contains("HUNK METADATA OMITTED"), "metadata marker missing")
        XCTAssertTrue(prompt.contains("hunks omitted"), "omission count missing")
        XCTAssertTrue(prompt.contains("HUNK PATCH CONTENT OMITTED"), "patch omission marker missing")
    }
}
