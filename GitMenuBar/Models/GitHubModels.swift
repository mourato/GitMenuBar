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
