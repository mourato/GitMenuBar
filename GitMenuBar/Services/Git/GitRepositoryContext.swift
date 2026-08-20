import Foundation

struct RepositoryOperationContext: Sendable, Equatable {
    let repositoryPath: String
    let branchName: String
    let refreshGeneration: Int
}

final class GitRepositoryContext: @unchecked Sendable {
    private let defaults: UserDefaults
    private let overridePath: String?

    init(
        defaults: UserDefaults = .standard,
        overridePath: String? = nil
    ) {
        self.defaults = defaults
        self.overridePath = overridePath
    }

    var repositoryPath: String {
        get {
            if let overridePath {
                return overridePath
            }
            return defaults.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
        }
        set {
            guard overridePath == nil else {
                return
            }
            defaults.set(newValue, forKey: AppPreferences.Keys.gitRepoPath)
        }
    }

    static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

struct GitRefreshSession {
    let repositoryPath: String
    let generation: Int
    let isCurrent: @MainActor () -> Bool
    let fastCompletion: @MainActor @Sendable () -> Void
}
