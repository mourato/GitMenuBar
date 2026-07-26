import Foundation

enum GitHubRemoteURLParser {
    static func parse(_ remoteURL: String) -> GitHubRemoteReference? {
        var normalized = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("git@github.com:") {
            normalized = normalized.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
        }

        if normalized.hasSuffix(".git") {
            normalized = String(normalized.dropLast(4))
        }

        guard let url = URL(string: normalized),
              url.host?.contains("github.com") == true
        else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else {
            return nil
        }

        return GitHubRemoteReference(
            owner: pathComponents[0],
            repository: pathComponents[1]
        )
    }

    static func normalizedWebURL(from remoteURL: String) -> String {
        guard let reference = parse(remoteURL) else {
            return remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return "https://github.com/\(reference.owner)/\(reference.repository)"
    }

    static func commitURL(owner: String, repository: String, sha: String) -> URL? {
        percentEncodedGitHubWebURL(pathComponents: [owner, repository, "commit", sha])
    }

    static func commitURL(remoteURL: String, sha: String) -> URL? {
        guard let reference = parse(remoteURL) else {
            return nil
        }
        return commitURL(owner: reference.owner, repository: reference.repository, sha: sha)
    }

    static func blobURL(owner: String, repository: String, sha: String, path: String) -> URL? {
        let normalizedPath = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !normalizedPath.isEmpty else {
            return nil
        }
        return percentEncodedGitHubWebURL(
            pathComponents: [owner, repository, "blob", sha] + normalizedPath
        )
    }

    static func blobURL(remoteURL: String, sha: String, path: String) -> URL? {
        guard let reference = parse(remoteURL) else {
            return nil
        }
        return blobURL(
            owner: reference.owner,
            repository: reference.repository,
            sha: sha,
            path: path
        )
    }

    private static func percentEncodedGitHubWebURL(pathComponents: [String]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.percentEncodedPath = "/" + pathComponents
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
            .joined(separator: "/")
        return components.url
    }
}
