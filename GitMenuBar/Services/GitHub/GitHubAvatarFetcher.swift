import Foundation

/// Fetches commit author avatars from the public GitHub API without any
/// authentication. Private repositories return nil; callers fall back to
/// initials, which is also the result when the network is unavailable.
enum GitHubAvatarFetcher {
    private static let cache = CommitAvatarCache()

    static func avatarURL(owner: String, repo: String, commitHash: String, authorEmail: String?) async -> URL? {
        let commitKey = "commit:\(owner.lowercased())/\(repo.lowercased())/\(commitHash.lowercased())"
        var authorKeys: [String] = []
        if let emailKey = authorEmailKey(owner: owner, repo: repo, email: authorEmail) {
            authorKeys.append(emailKey)
        }

        switch await cache.lookup(commitKey: commitKey, authorKeys: authorKeys) {
        case let .hit(cachedAvatar):
            return cachedAvatar
        case .miss:
            break
        }

        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(commitHash)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await cache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: nil)
                return nil
            }

            let decoder = JSONDecoder()
            let payload = try decoder.decode(GitHubCommitDetailsResponse.self, from: data)

            if let emailKey = authorEmailKey(
                owner: owner,
                repo: repo,
                email: payload.commit?.author?.email
            ) {
                authorKeys.append(emailKey)
            }

            if let loginKey = authorLoginKey(payload.author?.login) {
                authorKeys.append(loginKey)
            }

            guard let avatarUrl = payload.author?.avatarUrl, let avatarURL = URL(string: avatarUrl) else {
                await cache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: nil)
                return nil
            }

            await cache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: avatarURL)
            return avatarURL
        } catch {
            await cache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: nil)
            return nil
        }
    }

    private static func authorEmailKey(owner: String, repo: String, email: String?) -> String? {
        guard let email else {
            return nil
        }

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        return "author-email:\(owner.lowercased())/\(repo.lowercased())/\(normalized)"
    }

    private static func authorLoginKey(_ login: String?) -> String? {
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
