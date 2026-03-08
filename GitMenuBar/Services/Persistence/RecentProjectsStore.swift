import Foundation

final class RecentProjectsStore {
    private let defaults: UserDefaults
    private let key: String
    private let maxCount: Int

    init(
        defaults: UserDefaults = .standard,
        key: String = AppPreferences.Keys.recentRepoPaths,
        maxCount: Int = 5
    ) {
        self.defaults = defaults
        self.key = key
        self.maxCount = maxCount
    }

    func recentPaths() -> [String] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func add(_ path: String) {
        var current = recentPaths()
        current.removeAll { $0 == path }
        current.insert(path, at: 0)
        current = Array(current.prefix(maxCount))

        if let encoded = try? JSONEncoder().encode(current) {
            defaults.set(encoded, forKey: key)
        }
    }
}
