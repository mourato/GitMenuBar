@testable import GitMenuBar
import XCTest

final class GitHubIssueListServiceTests: XCTestCase {
    private let repository = GitHubRemoteReference(owner: "mourato", repository: "GitMenuBar")

    func testRequestReadsTheIssuesConnectionOnlySoPullRequestsNeverAppear() throws {
        let request = GitHubIssueListService.request(repository: repository, state: .closed, after: "abc", token: "t")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let query = try XCTUnwrap(json["query"] as? String)
        let variables = try XCTUnwrap(json["variables"] as? [String: Any])

        XCTAssertTrue(query.contains("repository(owner:$owner,name:$name){issues("))
        XCTAssertFalse(query.contains("pullRequests"))
        XCTAssertFalse(query.contains("search("))
        XCTAssertEqual(variables["owner"] as? String, "mourato")
        XCTAssertEqual(variables["name"] as? String, "GitMenuBar")
        XCTAssertEqual(variables["states"] as? [String], ["CLOSED"])
        XCTAssertEqual(variables["after"] as? String, "abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testParsesIssueFieldsLabelsAndNextCursor() throws {
        let page = try GitHubIssueListService.parse(Self.pageJSON(numbers: [7], hasNextPage: true, cursor: "c1"), statusCode: 200)
        let issue = try XCTUnwrap(page.issues.first)
        XCTAssertEqual(issue.number, 7)
        XCTAssertEqual(issue.title, "Issue 7")
        XCTAssertEqual(issue.state, .open)
        XCTAssertEqual(issue.authorLogin, "octocat")
        XCTAssertEqual(issue.labels, [GitHubIssueLabel(name: "bug", colorHex: "d73a4a")])
        XCTAssertEqual(issue.url.absoluteString, "https://github.com/mourato/GitMenuBar/issues/7")
        XCTAssertEqual(issue.createdAt, ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z"))
        XCTAssertEqual(page.nextCursor, "c1")

        let last = try GitHubIssueListService.parse(Self.pageJSON(numbers: [1], hasNextPage: false, cursor: "c9"), statusCode: 200)
        XCTAssertNil(last.nextCursor)
    }

    func testNextPageWithoutCursorFailsInsteadOfEndingListEarly() {
        let data = Self.pageJSON(numbers: [1], hasNextPage: true, cursor: nil)
        XCTAssertThrowsError(try GitHubIssueListService.parse(data, statusCode: 200)) {
            XCTAssertEqual($0 as? GitHubIssueListError, .requestFailed)
        }
    }

    func testMapsFailuresToDistinctErrors() {
        XCTAssertThrowsError(try GitHubIssueListService.parse(Data(), statusCode: 401)) {
            XCTAssertEqual($0 as? GitHubIssueListError, .notAuthenticated)
        }
        XCTAssertThrowsError(try GitHubIssueListService.parse(Data(), statusCode: 502)) {
            XCTAssertEqual($0 as? GitHubIssueListError, .requestFailed)
        }
        let notFound = #"{"data":{"repository":null},"errors":[{"type":"NOT_FOUND","message":"x"}]}"#
        XCTAssertThrowsError(try GitHubIssueListService.parse(Data(notFound.utf8), statusCode: 200)) {
            XCTAssertEqual($0 as? GitHubIssueListError, .repositoryNotFound)
        }
        XCTAssertThrowsError(try GitHubIssueListService.parse(Data("malformed".utf8), statusCode: 200)) {
            XCTAssertEqual($0 as? GitHubIssueListError, .requestFailed)
        }
    }

    func testMissingTokenFailsAsNotAuthenticatedWithoutNetwork() async {
        let service = GitHubIssueListService(tokenProvider: { nil }, transport: { _ in
            XCTFail("No request expected without a token")
            throw URLError(.cancelled)
        })
        do {
            _ = try await service.fetchPage(repository: repository, state: .open, after: nil)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error, .notAuthenticated)
        }
    }

    func testTransportErrorFailsAsRequestFailed() async {
        let service = GitHubIssueListService(tokenProvider: { "t" }, transport: { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await service.fetchPage(repository: repository, state: .open, after: nil)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error, .requestFailed)
        }
    }

    static func pageJSON(numbers: [Int], hasNextPage: Bool, cursor: String?) -> Data {
        let nodes = numbers.map { number in
            """
            {"number":\(number),"title":"Issue \(number)","state":"OPEN",\
            "url":"https://github.com/mourato/GitMenuBar/issues/\(number)",\
            "createdAt":"2026-01-02T03:04:05Z","updatedAt":"2026-01-03T03:04:05Z",\
            "author":{"login":"octocat"},"labels":{"nodes":[{"name":"bug","color":"d73a4a"}]}}
            """
        }
        let cursorJSON = cursor.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":\(hasNextPage),"endCursor":\(cursorJSON)},\
        "nodes":[\(nodes.joined(separator: ","))]}}}}
        """
        return Data(json.utf8)
    }
}

@MainActor
final class IssueListModelTests: XCTestCase {
    private let remoteA = "https://github.com/mourato/GitMenuBar.git"
    private let remoteB = "git@github.com:mourato/Other.git"

    private nonisolated static func issue(_ number: Int) -> GitHubIssue {
        GitHubIssue(
            number: number,
            title: "Issue \(number)",
            state: .open,
            authorLogin: "octocat",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            labels: [],
            url: URL(fileURLWithPath: "/issues/\(number)")
        )
    }

    func testLoadsAllPagesInOrderWithoutDuplicatesOrGaps() async {
        let pages: [String?: GitHubIssuePage] = [
            nil: GitHubIssuePage(issues: [1, 2, 3].map(Self.issue), nextCursor: "p2"),
            "p2": GitHubIssuePage(issues: [3, 4, 5].map(Self.issue), nextCursor: "p3"),
            "p3": GitHubIssuePage(issues: [6].map(Self.issue), nextCursor: nil)
        ]
        let model = IssueListModel { _, _, cursor in pages[cursor] ?? GitHubIssuePage(issues: [], nextCursor: nil) }

        await model.load(remoteURL: remoteA, state: .open)
        XCTAssertTrue(model.canLoadMore)
        await model.loadMore()
        await model.loadMore()

        XCTAssertEqual(model.issues.map(\.number), [1, 2, 3, 4, 5, 6])
        XCTAssertFalse(model.canLoadMore)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.repository, GitHubRemoteReference(owner: "mourato", repository: "GitMenuBar"))
    }

    func testLateResponseFromPreviousProjectIsIgnored() async {
        let gate = AsyncGate()
        let model = IssueListModel { repository, _, _ in
            if repository.repository == "GitMenuBar" {
                await gate.wait()
                return GitHubIssuePage(issues: [Self.issue(1)], nextCursor: nil)
            }
            return GitHubIssuePage(issues: [Self.issue(99)], nextCursor: nil)
        }

        let first = Task { await model.load(remoteURL: remoteA, state: .open) }
        await gate.waitUntilEntered()
        await model.load(remoteURL: remoteB, state: .open)
        await gate.open()
        await first.value

        XCTAssertEqual(model.issues.map(\.number), [99])
        XCTAssertEqual(model.repository?.repository, "Other")
    }

    func testStateFilterIsPassedAndLateOpenResponseIgnoredAfterSwitch() async {
        let gate = AsyncGate()
        let model = IssueListModel { _, state, _ in
            if state == .open {
                await gate.wait()
                return GitHubIssuePage(issues: [Self.issue(1)], nextCursor: nil)
            }
            return GitHubIssuePage(issues: [Self.issue(2)], nextCursor: nil)
        }

        let first = Task { await model.load(remoteURL: remoteA, state: .open) }
        await gate.waitUntilEntered()
        await model.load(remoteURL: remoteA, state: .closed)
        await gate.open()
        await first.value

        XCTAssertEqual(model.stateFilter, .closed)
        XCTAssertEqual(model.issues.map(\.number), [2])
    }

    func testFailureStatesAndRetry() async {
        let attempts = Counter()
        let model = IssueListModel { _, _, _ throws(GitHubIssueListError) in
            if await attempts.increment() == 1 {
                throw .requestFailed
            }
            return GitHubIssuePage(issues: [], nextCursor: nil)
        }

        await model.load(remoteURL: remoteA, state: .open)
        XCTAssertEqual(model.phase, .failed(.requestFailed))
        await model.reload()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.issues.isEmpty)
    }

    func testUnsupportedRemotesFailWithoutFetching() async {
        let model = IssueListModel { _, _, _ in
            XCTFail("No fetch expected")
            return GitHubIssuePage(issues: [], nextCursor: nil)
        }
        for remote in ["", "https://gitlab.com/o/r.git", "https://github.example.com/o/r.git"] {
            await model.load(remoteURL: remote, state: .open)
            XCTAssertEqual(model.phase, .failed(.unsupportedRepository), remote)
            XCTAssertNil(model.repository)
        }
    }

    func testNotAuthenticatedErrorSurfaces() async {
        let model = IssueListModel { _, _, _ throws(GitHubIssueListError) in throw .notAuthenticated }
        await model.load(remoteURL: remoteA, state: .open)
        XCTAssertEqual(model.phase, .failed(.notAuthenticated))
    }

    func testLoadMoreFailureKeepsShownIssuesAndAllowsRetry() async {
        let attempts = Counter()
        let model = IssueListModel { _, _, cursor throws(GitHubIssueListError) in
            guard cursor != nil else {
                return GitHubIssuePage(issues: [Self.issue(1)], nextCursor: "p2")
            }
            if await attempts.increment() == 1 {
                throw .requestFailed
            }
            return GitHubIssuePage(issues: [Self.issue(2)], nextCursor: nil)
        }

        await model.load(remoteURL: remoteA, state: .open)
        await model.loadMore()
        XCTAssertTrue(model.loadMoreFailed)
        XCTAssertEqual(model.issues.map(\.number), [1])
        await model.loadMore()
        XCTAssertFalse(model.loadMoreFailed)
        XCTAssertEqual(model.issues.map(\.number), [1, 2])
    }

    func testLabelTextColorStaysLegible() {
        XCTAssertTrue(IssueLabelColor(hex: "a2eeef").prefersDarkText)
        XCTAssertTrue(IssueLabelColor(hex: "ffffff").prefersDarkText)
        XCTAssertFalse(IssueLabelColor(hex: "7057ff").prefersDarkText)
        XCTAssertFalse(IssueLabelColor(hex: "000000").prefersDarkText)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        while waiters.isEmpty, !isOpen {
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private actor Counter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}
