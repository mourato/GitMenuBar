@testable import GitMenuBar
import XCTest

private struct LabelFixture {
    let id: String
    let name: String
    let color: String

    init(_ id: String, _ name: String, _ color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

final class GitHubIssueLabelServiceTests: XCTestCase {
    private let repository = GitHubRemoteReference(owner: "mourato", repository: "GitMenuBar")
    private let endpoint = URL(string: "https://api.github.com/graphql")!

    func testLabelsQueryReadsViewerPermissionAndRepositoryLabels() throws {
        let request = GitHubIssueLabelService.labelsRequest(repository: repository, after: "c1", token: "t")
        XCTAssertEqual(request.url, endpoint, "The token may only go to api.github.com")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let query = try XCTUnwrap(json["query"] as? String)
        let variables = try XCTUnwrap(json["variables"] as? [String: Any])

        XCTAssertTrue(query.contains("viewerPermission"))
        XCTAssertTrue(query.contains("labels(first:"))
        XCTAssertFalse(query.contains("pullRequests"))
        XCTAssertEqual(variables["owner"] as? String, "mourato")
        XCTAssertEqual(variables["name"] as? String, "GitMenuBar")
        XCTAssertEqual(variables["after"] as? String, "c1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testAddMutationTargetsOnlyTheChosenIssueAndLabel() throws {
        let request = GitHubIssueLabelService.addRequest(issueID: "I_42", labelID: "L_bug", token: "t")
        XCTAssertEqual(request.url, endpoint, "The token may only go to api.github.com")
        let json = try Self.bodyJSON(request)
        let query = try XCTUnwrap(json["query"] as? String)
        let variables = try XCTUnwrap(json["variables"] as? [String: Any])

        XCTAssertTrue(query.contains("addLabelsToLabelable"))
        XCTAssertFalse(query.contains("removeLabelsFromLabelable"))
        XCTAssertFalse(query.contains("updateIssue"))
        XCTAssertFalse(query.contains("replace"))
        XCTAssertEqual(variables["labelableId"] as? String, "I_42")
        XCTAssertEqual(variables["labelIds"] as? [String], ["L_bug"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testRemoveMutationTargetsOnlyTheChosenIssueAndLabel() throws {
        let request = GitHubIssueLabelService.removeRequest(issueID: "I_42", labelID: "L_bug", token: "t")
        XCTAssertEqual(request.url, endpoint, "The token may only go to api.github.com")
        let json = try Self.bodyJSON(request)
        let query = try XCTUnwrap(json["query"] as? String)
        let variables = try XCTUnwrap(json["variables"] as? [String: Any])

        XCTAssertTrue(query.contains("removeLabelsFromLabelable"))
        XCTAssertFalse(query.contains("addLabelsToLabelable"))
        XCTAssertFalse(query.contains("updateIssue"))
        XCTAssertEqual(variables["labelableId"] as? String, "I_42")
        XCTAssertEqual(variables["labelIds"] as? [String], ["L_bug"])
    }

    func testParsesLabelsAndWritePermission() throws {
        for permission in ["ADMIN", "MAINTAIN", "WRITE", "TRIAGE"] {
            let parsed = try GitHubIssueLabelService.parseLabels(
                Self.labelsJSON(permission: permission, labels: [LabelFixture("L_1", "bug", "d73a4a")]),
                statusCode: 200
            )
            XCTAssertTrue(parsed.canWrite, permission)
            XCTAssertEqual(parsed.labels, [GitHubIssueLabel(name: "bug", colorHex: "d73a4a", nodeID: "L_1")])
            XCTAssertNil(parsed.nextCursor)
        }

        let readOnly = try GitHubIssueLabelService.parseLabels(
            Self.labelsJSON(permission: "READ", labels: [LabelFixture("L_1", "bug", "d73a4a")]),
            statusCode: 200
        )
        XCTAssertFalse(readOnly.canWrite)
    }

    func testLabelsPagesFollowCursorUntilDone() async throws {
        let recorder = CursorRecorder()
        let service = GitHubIssueLabelService(tokenProvider: { "t" }, transport: { [endpoint] request in
            let cursor = Self.afterVariable(request)
            await recorder.append(cursor)
            let data = cursor == nil
                ? Self.labelsJSON(
                    permission: "WRITE",
                    labels: [LabelFixture("L_1", "bug", "d73a4a")],
                    hasNextPage: true,
                    cursor: "p2"
                )
                : Self.labelsJSON(permission: "WRITE", labels: [LabelFixture("L_2", "docs", "0075ca")])
            guard let response = HTTPURLResponse(
                url: endpoint,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ) else {
                throw URLError(.badServerResponse)
            }
            return (data, response)
        })

        let snapshot = try await service.fetchSnapshot(repository: repository)

        XCTAssertEqual(snapshot.labels.map(\.name), ["bug", "docs"])
        XCTAssertTrue(snapshot.canWrite)
        let cursors = await recorder.values
        XCTAssertEqual(cursors, [nil, "p2"])
    }

    func testMutationReturnsEveryConfirmedLabelSoOthersStayVisible() throws {
        let data = Self.mutationJSON(
            key: "addLabelsToLabelable",
            labels: [
                LabelFixture("L_1", "bug", "d73a4a"),
                LabelFixture("L_2", "docs", "0075ca"),
                LabelFixture("L_3", "enhancement", "a2eeef")
            ]
        )
        let labels = try GitHubIssueLabelService.parseMutation(data, statusCode: 200, adding: true)

        XCTAssertEqual(labels.map(\.name), ["bug", "docs", "enhancement"])
        XCTAssertEqual(labels.map(\.nodeID), ["L_1", "L_2", "L_3"])
    }

    func testRemoveMutationParsesTheRemainingLabels() throws {
        let data = Self.mutationJSON(key: "removeLabelsFromLabelable", labels: [LabelFixture("L_1", "bug", "d73a4a")])
        let labels = try GitHubIssueLabelService.parseMutation(data, statusCode: 200, adding: false)

        XCTAssertEqual(labels.map(\.name), ["bug"])
    }

    func testPermissionFailuresMapToForbidden() {
        for type in ["FORBIDDEN", "INSUFFICIENT_SCOPES"] {
            let data = Data(#"{"data":null,"errors":[{"type":"\#(type)","message":"denied"}]}"#.utf8)
            XCTAssertThrowsError(try GitHubIssueLabelService.parseMutation(data, statusCode: 200, adding: true)) {
                XCTAssertEqual($0 as? GitHubIssueLabelError, .forbidden, type)
            }
        }
        let messageOnly = Data(#"{"data":null,"errors":[{"message":"Resource not accessible by integration"}]}"#.utf8)
        XCTAssertThrowsError(try GitHubIssueLabelService.parseMutation(messageOnly, statusCode: 200, adding: true)) {
            XCTAssertEqual($0 as? GitHubIssueLabelError, .forbidden)
        }
        XCTAssertThrowsError(try GitHubIssueLabelService.parseLabels(Data(), statusCode: 403)) {
            XCTAssertEqual($0 as? GitHubIssueLabelError, .forbidden)
        }
    }

    func testOtherFailuresStayDistinct() {
        XCTAssertThrowsError(try GitHubIssueLabelService.parseLabels(Data(), statusCode: 401)) {
            XCTAssertEqual($0 as? GitHubIssueLabelError, .notAuthenticated)
        }
        let notFound = Data(#"{"data":{"repository":null},"errors":[{"type":"NOT_FOUND"}]}"#.utf8)
        XCTAssertThrowsError(try GitHubIssueLabelService.parseLabels(notFound, statusCode: 200)) {
            XCTAssertEqual($0 as? GitHubIssueLabelError, .repositoryNotFound)
        }
        let malformed = Data("nope".utf8)
        XCTAssertThrowsError(try GitHubIssueLabelService.parseMutation(malformed, statusCode: 200, adding: true)) {
            XCTAssertEqual($0 as? GitHubIssueLabelError, .requestFailed)
        }
        let missingPayload = Data(#"{"data":{}}"#.utf8)
        XCTAssertThrowsError(try GitHubIssueLabelService.parseMutation(missingPayload, statusCode: 200, adding: true)) {
            XCTAssertEqual($0 as? GitHubIssueLabelError, .requestFailed)
        }
    }

    func testMutationRequiresTokenWithoutNetwork() async {
        let service = GitHubIssueLabelService(tokenProvider: { nil }, transport: { _ in
            XCTFail("No request expected without a token")
            throw URLError(.cancelled)
        })
        do {
            _ = try await service.addLabel(issueID: "I_1", labelID: "L_1")
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error, .notAuthenticated)
        }
    }

    // MARK: - Fixtures

    private static func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private static func afterVariable(_ request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let variables = json["variables"] as? [String: Any]
        else {
            return nil
        }
        return variables["after"] as? String
    }

    private static func labelsJSON(
        permission: String,
        labels: [LabelFixture],
        hasNextPage: Bool = false,
        cursor: String? = nil
    ) -> Data {
        let nodes = labels.map { #"{"id":"\#($0.id)","name":"\#($0.name)","color":"\#($0.color)"}"# }
        let cursorJSON = cursor.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"data":{"repository":{"viewerPermission":"\(permission)",\
        "labels":{"pageInfo":{"hasNextPage":\(hasNextPage),"endCursor":\(cursorJSON)},\
        "nodes":[\(nodes.joined(separator: ","))]}}}}
        """
        return Data(json.utf8)
    }

    private static func mutationJSON(
        key: String,
        labels: [LabelFixture]
    ) -> Data {
        let nodes = labels.map { #"{"id":"\#($0.id)","name":"\#($0.name)","color":"\#($0.color)"}"# }
        let json = """
        {"data":{"\(key)":{"labelable":{"labels":{"nodes":[\(nodes.joined(separator: ","))]}}}}}
        """
        return Data(json.utf8)
    }
}

private actor CursorRecorder {
    private(set) var values: [String?] = []

    func append(_ value: String?) {
        values.append(value)
    }
}
