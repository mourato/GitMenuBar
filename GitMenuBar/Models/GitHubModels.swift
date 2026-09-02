import Foundation

struct GitHubRepository: Codable {
    let id: Int
    let name: String
    let fullName: String
    let htmlUrl: String
    let cloneUrl: String
    let `private`: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
        case `private`
    }
}

struct GitHubUser: Codable {
    let login: String
    let id: Int
    let name: String?
}

enum GitHubAPIError: Error {
    case unauthorized
    case notFound
    case conflict
    case networkError(Error)
    case invalidResponse
    case rateLimitExceeded
    case unknown(String)
}

struct GitHubRemoteReference: Equatable {
    let owner: String
    let repository: String
}

enum GitHubPullRequestReviewState: Equatable {
    case approved
    case changesRequested
    case reviewRequired
    case unknown
}

enum GitHubChecksState: Equatable {
    case passed
    case failing
    case pending
    case notRun
    case unknown
}

struct GitHubPullRequestSummary: Equatable, Identifiable {
    let number: Int
    let title: String
    let headBranch: String
    let isDraft: Bool
    let reviewState: GitHubPullRequestReviewState
    let checksState: GitHubChecksState
    let url: String

    var id: Int {
        number
    }

    var needsAction: Bool {
        reviewState == .changesRequested || checksState == .failing
    }

    var statusSummary: String {
        var parts: [String] = []
        if isDraft {
            parts.append("Draft")
        }
        switch reviewState {
        case .approved:
            parts.append("Approved")
        case .changesRequested:
            parts.append("Changes requested")
        case .reviewRequired:
            parts.append("Review required")
        case .unknown:
            break
        }
        switch checksState {
        case .passed:
            parts.append("CI passed")
        case .failing:
            parts.append("CI failing")
        case .pending:
            parts.append("CI running")
        case .notRun, .unknown:
            break
        }
        return parts.isEmpty ? "Status unavailable" : parts.joined(separator: " · ")
    }
}
