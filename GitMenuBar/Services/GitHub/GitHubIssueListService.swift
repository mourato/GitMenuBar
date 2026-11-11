import Foundation

enum GitHubIssueState: String, CaseIterable, Sendable {
    case open = "OPEN"
    case closed = "CLOSED"
}

struct GitHubIssueLabel: Hashable, Sendable {
    let name: String
    /// Six-digit hex color without `#`, as GitHub returns it.
    let colorHex: String
    /// GraphQL node ID used by the labelable mutations.
    let nodeID: String

    init(name: String, colorHex: String, nodeID: String = "") {
        self.name = name
        self.colorHex = colorHex
        self.nodeID = nodeID
    }
}

struct GitHubIssue: Identifiable, Equatable, Sendable {
    let number: Int
    let title: String
    let state: GitHubIssueState
    /// Nil when GitHub reports a deleted ("ghost") author.
    let authorLogin: String?
    let createdAt: Date
    let updatedAt: Date
    let labels: [GitHubIssueLabel]
    let url: URL
    /// GraphQL node ID used by the labelable mutations.
    let nodeID: String

    var id: Int {
        number
    }

    init(
        number: Int,
        title: String,
        state: GitHubIssueState,
        authorLogin: String?,
        createdAt: Date,
        updatedAt: Date,
        labels: [GitHubIssueLabel],
        url: URL,
        nodeID: String = ""
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.authorLogin = authorLogin
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.labels = labels
        self.url = url
        self.nodeID = nodeID
    }

    /// Keeps every field but `labels`, so a confirmed mutation updates only
    /// what GitHub changed.
    func replacingLabels(_ labels: [GitHubIssueLabel]) -> GitHubIssue {
        GitHubIssue(
            number: number,
            title: title,
            state: state,
            authorLogin: authorLogin,
            createdAt: createdAt,
            updatedAt: updatedAt,
            labels: labels,
            url: url,
            nodeID: nodeID
        )
    }
}

struct GitHubIssuePage: Equatable, Sendable {
    let issues: [GitHubIssue]
    /// Cursor for the next page; nil when this is the last page.
    let nextCursor: String?
}

enum GitHubIssueListError: Error, Equatable, Sendable {
    case notAuthenticated
    case unsupportedRepository
    case repositoryNotFound
    case requestFailed
}

/// Reads repository issues through the GitHub GraphQL API with the signed-in
/// token. The `issues` connection never contains pull requests, and cursor
/// pagination keeps pages free of gaps and duplicates while issues change.
struct GitHubIssueListService: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let pageSize = 50
    static let labelLimit = 100

    static let query = """
    query($owner:String!,$name:String!,$states:[IssueState!],$after:String){\
    repository(owner:$owner,name:$name){\
    issues(first:\(pageSize),after:$after,states:$states,orderBy:{field:CREATED_AT,direction:DESC}){\
    pageInfo{hasNextPage endCursor} \
    nodes{id number title state url createdAt updatedAt author{login} labels(first:\(labelLimit)){nodes{id name color}}}}}}
    """

    private static let endpoint = URL(string: "https://api.github.com/graphql")!

    let tokenProvider: @Sendable () async -> String?
    let transport: Transport

    init(
        tokenProvider: @escaping @Sendable () async -> String?,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    init(authManager: GitHubAuthManager) {
        self.init(tokenProvider: { await authManager.sessionSnapshot().token })
    }

    func fetchPage(
        repository: GitHubRemoteReference,
        state: GitHubIssueState,
        after cursor: String?
    ) async throws(GitHubIssueListError) -> GitHubIssuePage {
        guard let token = await tokenProvider() else {
            throw .notAuthenticated
        }
        let request = Self.request(repository: repository, state: state, after: cursor, token: token)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw .requestFailed
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try Self.parse(data, statusCode: statusCode)
    }

    static func request(
        repository: GitHubRemoteReference,
        state: GitHubIssueState,
        after cursor: String?,
        token: String
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = RequestBody(
            query: query,
            variables: RequestVariables(
                owner: repository.owner,
                name: repository.repository,
                states: [state.rawValue],
                after: cursor
            )
        )
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    static func parse(_ data: Data, statusCode: Int) throws(GitHubIssueListError) -> GitHubIssuePage {
        if statusCode == 401 {
            throw .notAuthenticated
        }
        guard statusCode == 200 else {
            throw .requestFailed
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let response = try? decoder.decode(RawResponse.self, from: data) else {
            throw .requestFailed
        }
        if response.errors?.contains(where: { $0.type == "NOT_FOUND" }) == true {
            throw .repositoryNotFound
        }
        guard let data = response.data else {
            throw .requestFailed
        }
        guard let connection = data.repository?.issues else {
            throw .repositoryNotFound
        }
        let issues = connection.nodes.compactMap { node -> GitHubIssue? in
            guard let state = GitHubIssueState(rawValue: node.state),
                  let url = URL(string: node.url)
            else {
                return nil
            }
            return GitHubIssue(
                number: node.number,
                title: node.title,
                state: state,
                authorLogin: node.author?.login,
                createdAt: node.createdAt,
                updatedAt: node.updatedAt,
                labels: node.labels?.nodes.map {
                    GitHubIssueLabel(name: $0.name, colorHex: $0.color, nodeID: $0.id ?? "")
                } ?? [],
                url: url,
                nodeID: node.id ?? ""
            )
        }
        let pageInfo = connection.pageInfo
        // A next page without a cursor would silently end the list early.
        guard !pageInfo.hasNextPage || pageInfo.endCursor != nil else {
            throw .requestFailed
        }
        return GitHubIssuePage(
            issues: issues,
            nextCursor: pageInfo.hasNextPage ? pageInfo.endCursor : nil
        )
    }

    private struct RequestBody: Encodable {
        let query: String
        let variables: RequestVariables
    }

    private struct RequestVariables: Encodable {
        let owner: String
        let name: String
        let states: [String]
        let after: String?
    }

    private struct RawResponse: Decodable {
        let data: RawData?
        let errors: [RawError]?
    }

    private struct RawError: Decodable {
        let type: String?
    }

    private struct RawData: Decodable {
        let repository: RawRepository?
    }

    private struct RawRepository: Decodable {
        let issues: RawConnection
    }

    private struct RawConnection: Decodable {
        let pageInfo: RawPageInfo
        let nodes: [RawIssue]
    }

    private struct RawPageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    private struct RawIssue: Decodable {
        let id: String?
        let number: Int
        let title: String
        let state: String
        let url: String
        let createdAt: Date
        let updatedAt: Date
        let author: RawAuthor?
        let labels: RawLabels?
    }

    private struct RawAuthor: Decodable {
        let login: String
    }

    private struct RawLabels: Decodable {
        let nodes: [RawLabel]
    }

    private struct RawLabel: Decodable {
        let id: String?
        let name: String
        let color: String
    }
}
