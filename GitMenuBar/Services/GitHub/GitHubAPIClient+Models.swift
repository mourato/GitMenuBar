import Foundation

extension GitHubAPIClient {
    enum CommitAvatarCacheLookup {
        case miss
        case hit(URL?)
    }

    actor CommitAvatarCache {
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

    struct GitHubCommitDetailsResponse: Decodable {
        let author: GitHubCommitAuthor?
        let commit: GitHubCommitPayload?
    }

    struct GitHubCommitPayload: Decodable {
        let author: GitHubCommitIdentity?
    }

    struct GitHubCommitIdentity: Decodable {
        let email: String?
    }

    enum GitHubCommitAuthorKey: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }

    struct GitHubCommitAuthor: Decodable {
        let login: String?
        let avatarUrl: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: GitHubCommitAuthorKey.self)
            login = try container.decodeIfPresent(String.self, forKey: .login)
            avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        }
    }
}
