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
}
