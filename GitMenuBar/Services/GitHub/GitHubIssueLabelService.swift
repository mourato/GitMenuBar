import Foundation

/// The labels available in one repository and whether the signed-in account
/// may change them. `viewerPermission` is the only source of that answer, so
/// the list can stay read-only without waiting for a failed mutation.
struct GitHubIssueLabelSnapshot: Equatable, Sendable {
    let labels: [GitHubIssueLabel]
    let canWrite: Bool
    /// Node ID of the repository, required to create a label. Empty when the
    /// reply did not carry it; creation then fails instead of guessing.
    let repositoryID: String

    init(labels: [GitHubIssueLabel], canWrite: Bool, repositoryID: String = "") {
        self.labels = labels
        self.canWrite = canWrite
        self.repositoryID = repositoryID
    }
}

enum GitHubIssueLabelError: Error, Equatable, Sendable {
    case notAuthenticated
    case repositoryNotFound
    case forbidden
    /// GitHub already has a label with the requested name.
    case labelNameTaken
    /// GitHub rejected the label details, for example an overlong name.
    case invalidLabel
    case requestFailed
}

/// One page of repository labels plus the viewer's permission, read from the
/// same response so the picker never offers an action GitHub would reject.
struct GitHubIssueLabelPage: Equatable, Sendable {
    let labels: [GitHubIssueLabel]
    let canWrite: Bool
    /// Repository node ID used by `createLabel`.
    let repositoryID: String
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
    repository(owner:$owner,name:$name){id viewerPermission \
    labels(first:\(labelPageSize),after:$after){pageInfo{hasNextPage endCursor} nodes{id name color}}}}
    """

    static let createMutation = """
    mutation($repositoryId:ID!,$name:String!,$color:String!,$description:String){\
    createLabel(input:{repositoryId:$repositoryId,name:$name,color:$color,description:$description}){\
    label{id name color}}}
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
        var repositoryID = ""
        var cursor: String?
        var isFirstPage = true
        repeat {
            let request = Self.labelsRequest(repository: repository, after: cursor, token: token)
            let (data, response) = try await send(request)
            let page = try Self.parseLabels(data, statusCode: statusCode(of: response))
            if isFirstPage {
                canWrite = page.canWrite
                repositoryID = page.repositoryID
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
        return GitHubIssueLabelSnapshot(labels: labels, canWrite: canWrite, repositoryID: repositoryID)
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

    /// Creates one repository label and returns it as GitHub confirms it. The
    /// caller adds it to the picker; creating never applies it to an issue.
    func createLabel(
        repositoryID: String,
        name: String,
        color: String,
        description: String?
    ) async throws(GitHubIssueLabelError) -> GitHubIssueLabel {
        guard let token = await tokenProvider() else {
            throw .notAuthenticated
        }
        guard !repositoryID.isEmpty else {
            throw .requestFailed
        }
        let request = Self.createRequest(
            repositoryID: repositoryID,
            name: name,
            color: color,
            description: description,
            token: token
        )
        let (data, response) = try await send(request)
        return try Self.parseCreatedLabel(data, statusCode: statusCode(of: response))
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

    static func createRequest(
        repositoryID: String,
        name: String,
        color: String,
        description: String?,
        token: String
    ) -> URLRequest {
        request(
            query: createMutation,
            variables: CreateLabelVariables(
                repositoryId: repositoryID,
                name: name,
                color: color,
                description: description
            ),
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
            repositoryID: repository.id ?? "",
            nextCursor: pageInfo.hasNextPage ? pageInfo.endCursor : nil
        )
    }

    static func parseCreatedLabel(
        _ data: Data,
        statusCode: Int
    ) throws(GitHubIssueLabelError) -> GitHubIssueLabel {
        try checkStatus(statusCode)
        let decoder = JSONDecoder()
        guard let response = try? decoder.decode(CreateLabelResponse.self, from: data) else {
            throw .requestFailed
        }
        if let error = createError(response.errors) {
            throw error
        }
        guard let label = response.data?.createLabel?.label else {
            throw .requestFailed
        }
        return GitHubIssueLabel(name: label.name, colorHex: label.color, nodeID: label.id)
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
        if let permission = permissionError(errors) {
            return permission
        }
        return .requestFailed
    }

    /// Creation failures need their own mapping: a taken name and invalid
    /// details are user-fixable, so they stay distinct from a failed request.
    private static func createError(_ errors: [RawError]?) -> GitHubIssueLabelError? {
        guard let errors, !errors.isEmpty else { return nil }
        if errors.contains(where: { $0.type == "NOT_FOUND" }) {
            return .repositoryNotFound
        }
        if let permission = permissionError(errors) {
            return permission
        }
        let takenName = errors.contains { error in
            let message = error.message ?? ""
            return message.range(of: "already been taken", options: .caseInsensitive) != nil
                || message.range(of: "already exists", options: .caseInsensitive) != nil
                || message.range(of: "must be unique", options: .caseInsensitive) != nil
        }
        if takenName {
            return .labelNameTaken
        }
        let invalid = errors.contains { error in
            if error.type == "UNPROCESSABLE" {
                return true
            }
            return error.message?.range(of: "invalid", options: .caseInsensitive) != nil
        }
        return invalid ? .invalidLabel : .requestFailed
    }

    private static func permissionError(_ errors: [RawError]) -> GitHubIssueLabelError? {
        let forbidden = errors.contains { error in
            let message = error.message ?? ""
            let mentionsPermission = message.range(of: "permission", options: .caseInsensitive) != nil
                || message.range(of: "not accessible", options: .caseInsensitive) != nil
            return error.type == "FORBIDDEN"
                || error.type == "INSUFFICIENT_SCOPES"
                || mentionsPermission
        }
        return forbidden ? .forbidden : nil
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

    private struct CreateLabelVariables: Encodable {
        let repositoryId: String
        let name: String
        let color: String
        let description: String?
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
        let id: String?
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

    private struct CreateLabelResponse: Decodable {
        let data: CreateLabelData?
        let errors: [RawError]?
    }

    private struct CreateLabelData: Decodable {
        let createLabel: CreateLabelPayload?
    }

    private struct CreateLabelPayload: Decodable {
        let label: RawLabel?
    }

    private struct RawError: Decodable {
        let type: String?
        let message: String?
    }
}
