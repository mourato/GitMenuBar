//
//  GitHubAPIClient.swift
//  GitMenuBar
//

import Foundation

class GitHubAPIClient {
    private let baseURL = "https://api.github.com"
    private let authManager: GitHubAuthManager

    private static let commitAvatarCache = CommitAvatarCache()

    init(authManager: GitHubAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Create Repository

    func createRepository(name: String, isPrivate: Bool, description: String? = nil) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/user/repos")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "name": name,
            "private": isPrivate,
            "auto_init": false // Don't create README, we'll push our own initial commit
        ]

        if let description = description {
            body["description"] = description
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 201:
                // Success
                let decoder = JSONDecoder()
                return try decoder.decode(GitHubRepository.self, from: data)
            case 401:
                throw GitHubAPIError.unauthorized
            case 404:
                throw GitHubAPIError.notFound
            case 422:
                // Repository already exists
                throw GitHubAPIError.conflict
            case 429:
                throw GitHubAPIError.rateLimitExceeded
            default:
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                if let message {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }

    // MARK: - Check Repository Exists

    func checkRepositoryExists(name: String) async throws -> Bool {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }

        guard !authManager.username.isEmpty else {
            return false
        }

        let url = URL(string: "\(baseURL)/repos/\(authManager.username)/\(name)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }

            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Get Repository

    func getRepository(name: String) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }

        guard !authManager.username.isEmpty else {
            throw GitHubAPIError.unknown("Username not available")
        }

        return try await getRepository(owner: authManager.username, name: name)
    }

    func getRepository(owner: String, name: String) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/repos/\(owner)/\(name)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                return try decoder.decode(GitHubRepository.self, from: data)
            case 401:
                throw GitHubAPIError.unauthorized
            case 404:
                throw GitHubAPIError.notFound
            default:
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                if let message {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }

    // MARK: - Check Any Repository URL Exists

    func checkRepositoryURLExists(owner: String, repo: String) async -> Bool {
        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        // Add auth if available (for private repos), but don't require it
        if let token = authManager.getStoredToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Commit Details

    func fetchCommitAuthorAvatarURL(
        owner: String,
        repo: String,
        commitHash: String,
        authorEmail: String? = nil
    ) async -> URL? {
        let commitKey = commitAvatarCommitKey(owner: owner, repo: repo, commitHash: commitHash)
        var authorKeys: [String] = []

        if let emailKey = authorEmailCacheKey(owner: owner, repo: repo, email: authorEmail) {
            authorKeys.append(emailKey)
        }

        switch await Self.commitAvatarCache.lookup(commitKey: commitKey, authorKeys: authorKeys) {
        case let .hit(cachedAvatar):
            return cachedAvatar
        case .miss:
            break
        }

        let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/commits/\(commitHash)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        if let token = authManager.getStoredToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let decoder = JSONDecoder()
            let payload = try decoder.decode(GitHubCommitDetailsResponse.self, from: data)

            if let emailKey = authorEmailCacheKey(
                owner: owner,
                repo: repo,
                email: payload.commit?.author?.email
            ) {
                authorKeys.append(emailKey)
            }

            if let loginKey = authorLoginCacheKey(payload.author?.login) {
                authorKeys.append(loginKey)
            }

            guard let avatarUrl = payload.author?.avatarUrl, let avatarURL = URL(string: avatarUrl) else {
                await Self.commitAvatarCache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: nil)
                return nil
            }

            await Self.commitAvatarCache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: avatarURL)
            return avatarURL
        } catch {
            await Self.commitAvatarCache.store(commitKey: commitKey, authorKeys: authorKeys, avatarURL: nil)
            return nil
        }
    }

    private func commitAvatarCommitKey(owner: String, repo: String, commitHash: String) -> String {
        "commit:\(owner.lowercased())/\(repo.lowercased())/\(commitHash.lowercased())"
    }

    private func authorEmailCacheKey(owner: String, repo: String, email: String?) -> String? {
        guard let email else {
            return nil
        }

        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        return "author-email:\(owner.lowercased())/\(repo.lowercased())/\(normalized)"
    }

    private func authorLoginCacheKey(_ login: String?) -> String? {
        guard let login else {
            return nil
        }

        let normalized = login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        return "author-login:\(normalized)"
    }

    // MARK: - Get Current User

    func getCurrentUser() async throws -> GitHubUser {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw GitHubAPIError.unauthorized
            }

            let decoder = JSONDecoder()
            return try decoder.decode(GitHubUser.self, from: data)
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }

    // MARK: - Delete Repository

    func deleteRepository(owner: String, name: String) async throws {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/repos/\(owner)/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 204:
                // Success - repository deleted
                return
            case 401:
                throw GitHubAPIError.unauthorized
            case 403:
                throw GitHubAPIError.unknown("Forbidden - token may not have delete_repo scope")
            case 404:
                throw GitHubAPIError.notFound
            default:
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                if let message {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }

    // MARK: - Update Repository Visibility

    func updateRepositoryVisibility(owner: String, name: String, isPrivate: Bool) async throws -> GitHubRepository {
        guard let token = authManager.getStoredToken() else {
            throw GitHubAPIError.unauthorized
        }

        let url = URL(string: "\(baseURL)/repos/\(owner)/\(name)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "private": isPrivate
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                // Success
                let decoder = JSONDecoder()
                return try decoder.decode(GitHubRepository.self, from: data)
            case 401:
                throw GitHubAPIError.unauthorized
            case 403:
                throw GitHubAPIError.unknown("Forbidden - token may not have repo scope")
            case 404:
                throw GitHubAPIError.notFound
            case 422:
                throw GitHubAPIError.unknown("Unprocessable Entity - validation failed")
            default:
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                if let message {
                    throw GitHubAPIError.unknown(message)
                }
                throw GitHubAPIError.unknown("Status code: \(httpResponse.statusCode)")
            }
        } catch let error as GitHubAPIError {
            throw error
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
}
