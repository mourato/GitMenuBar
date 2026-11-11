import Foundation

/// The labels available in one repository and whether the signed-in account
/// may change them. `viewerPermission` is the only source of that answer, so
/// the list can stay read-only without waiting for a failed mutation.
struct GitHubIssueLabelSnapshot: Equatable, Sendable {
    let labels: [GitHubIssueLabel]
    let canWrite: Bool
}

enum GitHubIssueLabelError: Error, Equatable, Sendable {
    case notAuthenticated
    case repositoryNotFound
    case forbidden
    case requestFailed
}

/// One page of repository labels plus the viewer's permission, read from the
/// same response so the picker never offers an action GitHub would reject.
struct GitHubIssueLabelPage: Equatable, Sendable {
    let labels: [GitHubIssueLabel]
    let canWrite: Bool
    /// Cursor for the next page; nil when this is the last page.
    let nextCursor: String?
}

/// Reads repository labels and applies or removes one label at a time through
/// GitHub's labelable mutations. Each mutation names only the chosen issue and
/// label, so other labels, including concurrent changes, stay untouched.
struct GitHubIssueLabelService: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let labelPageSize = 100
    static let labelLimit = 100

    /// Permissions that may apply and remove labels. Triage can manage issue
    /// metadata without write access to code.
    static let writablePermissions: Set<String> = ["ADMIN", "MAINTAIN", "WRITE", "TRIAGE"]

    static let labelsQuery = """
    query($owner:String!,$name:String!,$after:String){\
    repository(owner:$owner,name:$name){viewerPermission \
    labels(first:\(labelPageSize),after:$after){pageInfo{hasNextPage endCursor} nodes{id name color}}}}
    """

    static let addMutation = """
    mutation($labelableId:ID!,$labelIds:[ID!]!){\
    addLabelsToLabelable(input:{labelableId:$labelableId,labelIds:$labelIds}){\
    labelable{... on Issue{number labels(first:\(labelLimit)){nodes{id name color}}}}}}
    """

    static let removeMutation = """
    mutation($labelableId:ID!,$labelIds:[ID!]!){\
    removeLabelsFromLabelable(input:{labelableId:$labelableId,labelIds:$labelIds}){\
    labelable{... on Issue{number labels(first:\(labelLimit)){nodes{id name color}}}}}}
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

    /// Follows label pages so the picker offers every label in the repository.
    func fetchSnapshot(
        repository: GitHubRemoteReference
    ) async throws(GitHubIssueLabelError) -> GitHubIssueLabelSnapshot {
        guard let token = await tokenProvider() else {
            throw .notAuthenticated
        }
        var labels: [GitHubIssueLabel] = []
        var seenNames: Set<String> = []
        var canWrite = false
        var cursor: String?
        var isFirstPage = true
        repeat {
            let request = Self.labelsRequest(repository: repository, after: cursor, token: token)
            let (data, response) = try await send(request)
            let page = try Self.parseLabels(data, statusCode: statusCode(of: response))
            if isFirstPage {
                canWrite = page.canWrite
                isFirstPage = false
            }
            for label in page.labels where seenNames.insert(label.name).inserted {
                labels.append(label)
            }
            if page.nextCursor == nil {
                break
            }
            cursor = page.nextCursor
        } while true
        return GitHubIssueLabelSnapshot(labels: labels, canWrite: canWrite)
    }

    /// Adds the chosen label and returns the issue's labels as GitHub confirms
    /// them after the mutation.
    func addLabel(issueID: String, labelID: String) async throws(GitHubIssueLabelError) -> [GitHubIssueLabel] {
        guard let token = await tokenProvider() else {
            throw .notAuthenticated
        }
        let request = Self.addRequest(issueID: issueID, labelID: labelID, token: token)
        let (data, response) = try await send(request)
        return try Self.parseMutation(data, statusCode: statusCode(of: response), adding: true)
    }

    func removeLabel(issueID: String, labelID: String) async throws(GitHubIssueLabelError) -> [GitHubIssueLabel] {
        guard let token = await tokenProvider() else {
            throw .notAuthenticated
        }
        let request = Self.removeRequest(issueID: issueID, labelID: labelID, token: token)
        let (data, response) = try await send(request)
        return try Self.parseMutation(data, statusCode: statusCode(of: response), adding: false)
    }

    private func send(_ request: URLRequest) async throws(GitHubIssueLabelError) -> (Data, URLResponse) {
        do {
            return try await transport(request)
        } catch {
            throw .requestFailed
        }
    }

    private func statusCode(of response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    // MARK: - Requests

    static func labelsRequest(
        repository: GitHubRemoteReference,
        after cursor: String?,
        token: String
    ) -> URLRequest {
        request(
            query: labelsQuery,
            variables: LabelsVariables(owner: repository.owner, name: repository.repository, after: cursor),
            token: token
        )
    }

    static func addRequest(issueID: String, labelID: String, token: String) -> URLRequest {
        request(
            query: addMutation,
            variables: LabelIdsVariables(labelableId: issueID, labelIds: [labelID]),
            token: token
        )
    }

    static func removeRequest(issueID: String, labelID: String, token: String) -> URLRequest {
        request(
            query: removeMutation,
            variables: LabelIdsVariables(labelableId: issueID, labelIds: [labelID]),
            token: token
        )
    }

    private static func request(
        query: String,
        variables: some Encodable,
        token: String
    ) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RequestBody(query: query, variables: variables))
        return request
    }

    // MARK: - Parsing

    static func parseLabels(
        _ data: Data,
        statusCode: Int
    ) throws(GitHubIssueLabelError) -> GitHubIssueLabelPage {
        try checkStatus(statusCode)
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(LabelsResponse.self, from: data) else {
            throw .requestFailed
        }
        if let error = graphQLError(response.errors) {
            throw error
        }
        guard let repository = response.data?.repository else {
            throw .repositoryNotFound
        }
        let pageInfo = repository.labels.pageInfo
        guard !pageInfo.hasNextPage || pageInfo.endCursor != nil else {
            throw .requestFailed
        }
        return GitHubIssueLabelPage(
            labels: repository.labels.nodes.map { GitHubIssueLabel(name: $0.name, colorHex: $0.color, nodeID: $0.id) },
            canWrite: writablePermissions.contains(repository.viewerPermission ?? ""),
            nextCursor: pageInfo.hasNextPage ? pageInfo.endCursor : nil
        )
    }

    static func parseMutation(
        _ data: Data,
        statusCode: Int,
        adding: Bool
    ) throws(GitHubIssueLabelError) -> [GitHubIssueLabel] {
        try checkStatus(statusCode)
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(MutationResponse.self, from: data) else {
            throw .requestFailed
        }
        if let error = graphQLError(response.errors) {
            throw error
        }
        let payload = adding ? response.data?.addLabelsToLabelable : response.data?.removeLabelsFromLabelable
        guard let labels = payload?.labelable?.labels else {
            throw .requestFailed
        }
        return labels.nodes.map { GitHubIssueLabel(name: $0.name, colorHex: $0.color, nodeID: $0.id) }
    }

    private static func checkStatus(_ statusCode: Int) throws(GitHubIssueLabelError) {
        if statusCode == 401 {
            throw .notAuthenticated
        }
        if statusCode == 403 {
            throw .forbidden
        }
    }

    private static func graphQLError(_ errors: [RawError]?) -> GitHubIssueLabelError? {
        guard let errors, !errors.isEmpty else { return nil }
        if errors.contains(where: { $0.type == "NOT_FOUND" }) {
            return .repositoryNotFound
        }
        let forbidden = errors.contains { error in
            let message = error.message ?? ""
            let mentionsPermission = message.range(of: "permission", options: .caseInsensitive) != nil
                || message.range(of: "not accessible", options: .caseInsensitive) != nil
            return error.type == "FORBIDDEN"
                || error.type == "INSUFFICIENT_SCOPES"
                || mentionsPermission
        }
        return forbidden ? .forbidden : .requestFailed
    }

    // MARK: - Request bodies

    private struct RequestBody<Variables: Encodable>: Encodable {
        let query: String
        let variables: Variables
    }

    private struct LabelsVariables: Encodable {
        let owner: String
        let name: String
        let after: String?
    }

    private struct LabelIdsVariables: Encodable {
        let labelableId: String
        let labelIds: [String]
    }

    // MARK: - Response bodies

    private struct LabelsResponse: Decodable {
        let data: LabelsData?
        let errors: [RawError]?
    }

    private struct LabelsData: Decodable {
        let repository: RawRepository?
    }

    private struct RawRepository: Decodable {
        let viewerPermission: String?
        let labels: RawLabelConnection
    }

    private struct RawLabelConnection: Decodable {
        let pageInfo: RawPageInfo
        let nodes: [RawLabel]
    }

    private struct RawPageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    private struct RawLabel: Decodable {
        let id: String
        let name: String
        let color: String
    }

    private struct MutationResponse: Decodable {
        let data: MutationData?
        let errors: [RawError]?
    }

    private struct MutationData: Decodable {
        let addLabelsToLabelable: MutationPayload?
        let removeLabelsFromLabelable: MutationPayload?
    }

    private struct MutationPayload: Decodable {
        let labelable: RawLabelable?
    }

    private struct RawLabelable: Decodable {
        let labels: RawIssuedLabelConnection
    }

    private struct RawIssuedLabelConnection: Decodable {
        let nodes: [RawLabel]
    }

    private struct RawError: Decodable {
        let type: String?
        let message: String?
    }
}
