@testable import GitMenuBar
import XCTest

final class CommitHistoryParserTests: XCTestCase {
    private let parser = CommitHistoryParser(runner: GitCommandRunner())

    private struct CommitRecord {
        let hash: String
        let shortHash: String
        let timestamp: TimeInterval
        let authorName: String
        let authorEmail: String
        let parents: String
        let subject: String
        let body: String
        let stats: [String]
    }

    func testParseReturnsCommitWithBodyAndStats() {
        let output = makeRecord(
            CommitRecord(
                hash: "abcdef1234567890",
                shortHash: "abcdef1",
                timestamp: 1_709_856_000,
                authorName: "Renato",
                authorEmail: "renato@example.com",
                parents: "1234567",
                subject: "feat(history): show commit details",
                body: """
                - Add delayed hover card
                - Render commit stats in footer
                """,
                stats: [
                    "12\t3\tGitMenuBar/Components/History/HistoryTimelineSectionView.swift",
                    "4\t0\tGitMenuBar/Services/Git/CommitHistoryParser.swift"
                ]
            )
        )

        let commits = parser.parse(output)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.id, "abcdef1234567890")
        XCTAssertEqual(commits.first?.shortHash, "abcdef1")
        XCTAssertEqual(commits.first?.subject, "feat(history): show commit details")
        XCTAssertEqual(commits.first?.body, "- Add delayed hover card\n- Render commit stats in footer")
        XCTAssertEqual(commits.first?.authorName, "Renato")
        XCTAssertEqual(commits.first?.authorEmail, "renato@example.com")
        XCTAssertEqual(commits.first?.isMergeCommit, false)
        XCTAssertEqual(commits.first?.stats, CommitStats(filesChanged: 2, insertions: 16, deletions: 3))
        XCTAssertEqual(
            commits.first?.changedFiles,
            [
                CommitFileChange(
                    path: "GitMenuBar/Components/History/HistoryTimelineSectionView.swift",
                    lineDiff: LineDiffStats(added: 12, removed: 3)
                ),
                CommitFileChange(
                    path: "GitMenuBar/Services/Git/CommitHistoryParser.swift",
                    lineDiff: LineDiffStats(added: 4, removed: 0)
                )
            ]
        )
        XCTAssertEqual(commits.first?.committedAt.timeIntervalSince1970, 1_709_856_000)
    }

    func testParseHandlesEmptyBodyAndBinaryNumstat() {
        let output = makeRecord(
            CommitRecord(
                hash: "1234567890abcdef",
                shortHash: "1234567",
                timestamp: 1_709_942_400,
                authorName: "Renato",
                authorEmail: "renato@example.com",
                parents: "abcdef0",
                subject: "fix(parser): support binary files",
                body: "",
                stats: [
                    "-\t-\tImages/icon.png"
                ]
            )
        )

        let commits = parser.parse(output)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.body, "")
        XCTAssertEqual(commits.first?.stats, CommitStats(filesChanged: 1, insertions: 0, deletions: 0))
        XCTAssertEqual(
            commits.first?.changedFiles,
            [
                CommitFileChange(
                    path: "Images/icon.png",
                    lineDiff: LineDiffStats(added: 0, removed: 0)
                )
            ]
        )
    }

    func testParseDeduplicatesHashesFromReflog() {
        let output = [
            makeRecord(
                CommitRecord(
                    hash: "duplicatehash",
                    shortHash: "dup1234",
                    timestamp: 1_709_942_400,
                    authorName: "Renato",
                    authorEmail: "renato@example.com",
                    parents: "parent1",
                    subject: "feat: latest version",
                    body: "",
                    stats: ["1\t0\tREADME.md"]
                )
            ),
            makeRecord(
                CommitRecord(
                    hash: "duplicatehash",
                    shortHash: "dup1234",
                    timestamp: 1_709_856_000,
                    authorName: "Renato",
                    authorEmail: "renato@example.com",
                    parents: "parent2",
                    subject: "feat: older duplicate",
                    body: "ignored",
                    stats: ["9\t9\tREADME.md"]
                )
            ),
            makeRecord(
                CommitRecord(
                    hash: "uniquehash",
                    shortHash: "uniq123",
                    timestamp: 1_709_769_600,
                    authorName: "Renato",
                    authorEmail: "renato@example.com",
                    parents: "parent0",
                    subject: "chore: previous commit",
                    body: "",
                    stats: ["2\t1\tSources/App.swift"]
                )
            )
        ].joined()

        let commits = parser.parse(output)

        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits.map(\.id), ["duplicatehash", "uniquehash"])
        XCTAssertEqual(commits.first?.subject, "feat: latest version")
        XCTAssertEqual(commits.first?.stats, CommitStats(filesChanged: 1, insertions: 1, deletions: 0))
    }

    func testParseFiltersCheckpointRefs() {
        let output = [
            makeRecord(
                CommitRecord(
                    hash: "checkpointhash",
                    shortHash: "check12",
                    timestamp: 1_709_942_400,
                    authorName: "Automation",
                    authorEmail: "bot@example.com",
                    parents: "parent1",
                    subject: "t3 checkpoint ref=refs/t3/checkpoints/example/turn/1",
                    body: "",
                    stats: ["1\t0\tREADME.md"]
                )
            ),
            makeRecord(
                CommitRecord(
                    hash: "visiblehash",
                    shortHash: "visible",
                    timestamp: 1_709_856_000,
                    authorName: "Renato",
                    authorEmail: "renato@example.com",
                    parents: "parent2",
                    subject: "feat(history): keep visible commits only",
                    body: "",
                    stats: ["3\t1\tGitMenuBar/Services/Git/CommitHistoryParser.swift"]
                )
            )
        ].joined()

        let commits = parser.parse(output)

        XCTAssertEqual(commits.map(\.id), ["visiblehash"])
        XCTAssertEqual(commits.first?.subject, "feat(history): keep visible commits only")
    }

    func testParseMarksMergeCommits() {
        let output = makeRecord(
            CommitRecord(
                hash: "mergehash",
                shortHash: "merge12",
                timestamp: 1_709_942_400,
                authorName: "Renato",
                authorEmail: "renato@example.com",
                parents: "abc123 def456",
                subject: "Merge branch 'feature/history'",
                body: "",
                stats: ["1\t0\tREADME.md"]
            )
        )

        let commits = parser.parse(output)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.isMergeCommit, true)
    }

    func testFetchCommitHistoryDefaultsTo50Items() throws {
        let repoURL = try createTemporaryGitRepository(testName: #function)
        let runner = GitCommandRunner()
        let fetchParser = CommitHistoryParser(runner: runner)

        for index in 1 ... 60 {
            let fileURL = repoURL.appendingPathComponent("file-\(index).txt")
            try "value-\(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
            try runGit(["add", "."], in: repoURL)
            try runGit(["commit", "-m", "feat: commit \(index)"], in: repoURL)
        }

        let commits = fetchParser.fetchCommitHistory(in: repoURL.path)

        XCTAssertEqual(commits.count, 50)
    }

    private func makeRecord(_ record: CommitRecord) -> String {
        let recordSeparator = "\u{1e}"
        let fieldSeparator = "\u{1f}"
        let groupSeparator = "\u{1d}"

        return [
            recordSeparator,
            record.hash,
            fieldSeparator,
            record.shortHash,
            fieldSeparator,
            String(Int(record.timestamp)),
            fieldSeparator,
            record.authorName,
            fieldSeparator,
            record.authorEmail,
            fieldSeparator,
            record.parents,
            fieldSeparator,
            record.subject,
            fieldSeparator,
            record.body,
            groupSeparator,
            "\n",
            record.stats.joined(separator: "\n"),
            "\n"
        ].joined()
    }
}
