import Foundation

final class GitHubRepositoryService {
    private let authManager: GitHubAuthManager
    private lazy var apiClient = GitHubAPIClient(authManager: authManager)

    init(authManager: GitHubAuthManager) {
        self.authManager = authManager
    }

    func createOrFetchRepository(
        name: String,
        isPrivate: Bool,
        description: String? = nil
    ) async throws -> GitHubRepository {
        do {
            return try await apiClient.createRepository(
                name: name,
                isPrivate: isPrivate,
                description: description
            )
        } catch GitHubAPIError.conflict {
            return try await apiClient.getRepository(name: name)
        }
    }

    func deleteRepository(remoteURL: String) async throws {
        let reference = try remoteReference(from: remoteURL)
        try await apiClient.deleteRepository(owner: reference.owner, name: reference.repository)
    }

    func updateVisibility(
        remoteURL: String,
        isPrivate: Bool
    ) async throws -> GitHubRepository {
        let reference = try remoteReference(from: remoteURL)
        return try await apiClient.updateRepositoryVisibility(
            owner: reference.owner,
            name: reference.repository,
            isPrivate: isPrivate
        )
    }

    private func remoteReference(from remoteURL: String) throws -> GitHubRemoteReference {
        guard let reference = GitHubRemoteURLParser.parse(remoteURL) else {
            throw GitHubAPIError.unknown("Could not parse repository owner and name from remote URL")
        }

        return reference
    }
}
