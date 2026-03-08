import Foundation

final class GitRepositoryContext {
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
}
