import Foundation

/// Fetches commit author avatars from the public GitHub API without any
/// authentication. Private repositories return nil; callers fall back to
/// initials, which is also the result when the network is unavailable.
enum GitHubAvatarFetcher {
    private static let cache = CommitAvatarCache()

    static func avatarURL(owner: String, repo: String, commitHash: String, authorEmail: String?) async -> URL? {
        let commitKey = commitKey(owner: owner, repo: repo, commitHash: commitHash)
        var authorKeys = initialAuthorKeys(owner: owner, repo: repo, email: authorEmail)

        if case let .hit(cachedAvatar) = await cache.lookup(commitKey: commitKey, authorKeys: authorKeys) {
            return cachedAvatar
        }

        guard let payload = await fetchDetails(owner: owner, repo: repo, commitHash: commitHash) else {
            await cache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: nil)
            return nil
        }

        authorKeys += payload.authorKeys(owner: owner, repo: repo)
        guard let avatarURL = payload.avatarURL else {
            await cache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: nil)
            return nil
        }

        await cache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: avatarURL)
        return avatarURL
    }

    private static func commitKey(owner: String, repo: String, commitHash: String) -> String {
        "commit:\(owner.lowercased())/\(repo.lowercased())/\(commitHash.lowercased())"
    }

    private static func initialAuthorKeys(owner: String, repo: String, email: String?) -> [String] {
        guard let key = authorEmailKey(owner: owner, repo: repo, email: email) else {
            return []
        }
        return [key]
    }

    private static func fetchDetails(owner: String, repo: String, commitHash: String) async -> GitHubCommitDetailsResponse? {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(commitHash)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(GitHubCommitDetailsResponse.self, from: data)
        } catch {
            return nil
        }
    }

    fileprivate static func authorEmailKey(owner: String, repo: String, email: String?) -> String? {
        guard let email else {
            return nil
        }

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        return "author-email:\(owner.lowercased())/\(repo.lowercased())/\(normalized)"
    }

    fileprivate static func authorLoginKey(_ login: String?) -> String? {
        guard let login else {
            return nil
        }

        let normalized = login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        return "author-login:\(normalized)"
    }
}

private actor CommitAvatarCache {
    private var byCommit: [String: URL?] = [:]
    private var byAuthor: [String: URL] = [:]

    func lookup(commitKey: String, authorKeys: [String]) -> CommitAvatarCacheLookup {
        for key in authorKeys {
            if let avatarURL = byAuthor[key] {
                return .hit(avatarURL)
            }
        }

        if let cachedAvatar = byCommit[commitKey] {
            return .hit(cachedAvatar)
        }

        return .miss
    }

    func store(commitKey: String, authorKeys: [String], avatarURL: URL?) {
        byCommit[commitKey] = avatarURL

        guard let avatarURL else {
            return
        }

        for key in authorKeys {
            byAuthor[key] = avatarURL
        }
    }
}

private enum CommitAvatarCacheLookup {
    case miss
    case hit(URL?)
}

private struct GitHubCommitDetailsResponse: Decodable {
    let author: GitHubCommitAuthor?
    let commit: GitHubCommitPayload?

    var avatarURL: URL? {
        guard let avatarUrl = author?.avatarUrl else {
            return nil
        }
        return URL(string: avatarUrl)
    }

    func authorKeys(owner: String, repo: String) -> [String] {
        var keys: [String] = []
        if let key = GitHubAvatarFetcher.authorEmailKey(owner: owner, repo: repo, email: commit?.author?.email) {
            keys.append(key)
        }
        if let key = GitHubAvatarFetcher.authorLoginKey(author?.login) {
            keys.append(key)
        }
        return keys
    }
}

private struct GitHubCommitPayload: Decodable {
    let author: GitHubCommitIdentity?
}

private struct GitHubCommitIdentity: Decodable {
    let email: String?
}

private struct GitHubCommitAuthor: Decodable {
    let login: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}
