@testable import GitMenuBar
import XCTest

final class GitHubRepositoryResponseValidationTests: XCTestCase {
    func testCreationAcceptsCreatedStatus() throws {
        try GitHubRepositoryResponseValidator.validateCreationResponse(response(statusCode: 201), data: Data())
    }

    func testCreationMapsValidationFailureToConflict() {
        assertGitHubError(.conflict) {
            try GitHubRepositoryResponseValidator.validateCreationResponse(response(statusCode: 422), data: Data())
        }
    }

    func testDeletionAcceptsNoContentStatus() throws {
        try GitHubRepositoryResponseValidator.validateDeletionResponse(response(statusCode: 204), data: Data())
    }

    func testDeletionMapsForbiddenToDeleteScopeMessage() {
        assertGitHubError(.unknown("Forbidden - token may not have delete_repo scope")) {
            try GitHubRepositoryResponseValidator.validateDeletionResponse(response(statusCode: 403), data: Data())
        }
    }

    func testVisibilityAcceptsOkStatus() throws {
        try GitHubRepositoryResponseValidator.validateVisibilityResponse(response(statusCode: 200), data: Data())
    }

    func testVisibilityMapsValidationFailureToMessage() {
        assertGitHubError(.unknown("Unprocessable Entity - validation failed")) {
            try GitHubRepositoryResponseValidator.validateVisibilityResponse(response(statusCode: 422), data: Data())
        }
    }

    func testUnknownResponseUsesGitHubMessageWhenPresent() {
        let data = Data(#"{"message":"Repository access blocked"}"#.utf8)

        assertGitHubError(.unknown("Repository access blocked")) {
            try GitHubRepositoryResponseValidator.validateCreationResponse(response(statusCode: 500), data: data)
        }
    }

    private func response(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/repos/owner/repo")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private func assertGitHubError(
        _ expected: ExpectedGitHubError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            XCTFail("Expected GitHubAPIError", file: file, line: line)
        } catch let error as GitHubAPIError {
            XCTAssertTrue(expected.matches(error), file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum ExpectedGitHubError {
    case conflict
    case unknown(String)

    func matches(_ error: GitHubAPIError) -> Bool {
        switch (self, error) {
        case (.conflict, .conflict):
            true
        case let (.unknown(expected), .unknown(actual)):
            expected == actual
        default:
            false
        }
    }
}
