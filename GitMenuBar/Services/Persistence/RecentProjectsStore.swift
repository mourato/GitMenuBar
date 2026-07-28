import Foundation

struct ProjectReference: Codable, Equatable, Identifiable {
    let path: String
    var name: String

    var id: String {
        path
    }

    init(path: String, name: String? = nil) {
        self.path = RecentProjectsStore.normalize(path)
        self.name = Self.normalizedName(name, path: self.path)
    }

    private static func normalizedName(_ name: String?, path: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? PathDisplayFormatter.defaultProjectName(for: path) : trimmed
    }
}

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
        recentProjects().map(\.path)
    }

    func recentProjects() -> [ProjectReference] {
        guard let data = defaults.data(forKey: key) else { return [] }
        if let projects = try? JSONDecoder().decode([ProjectReference].self, from: data) {
            return normalized(projects)
        }
        if let paths = try? JSONDecoder().decode([String].self, from: data) {
            let projects = normalized(paths.map { ProjectReference(path: $0) })
            write(projects)
            return projects
        }
        return []
    }

    func add(_ path: String) {
        upsert(path: path)
    }

    func upsert(path: String, name: String? = nil) {
        let normalizedPath = Self.normalize(path)
        var current = recentProjects()
        let existing = current.first { $0.path == normalizedPath }
        let project = ProjectReference(path: normalizedPath, name: name ?? existing?.name)
        current.removeAll { $0.path == normalizedPath }
        current.insert(project, at: 0)
        write(Array(current.prefix(maxCount)))
    }

    func rename(path: String, name: String) {
        upsert(path: path, name: name)
    }

    func displayName(for path: String) -> String {
        guard !path.isEmpty else { return "" }
        return recentProjects().first { $0.path == Self.normalize(path) }?.name
            ?? PathDisplayFormatter.defaultProjectName(for: path)
    }

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func normalized(_ projects: [ProjectReference]) -> [ProjectReference] {
        var seen = Set<String>()
        return projects.compactMap { project in
            let normalized = ProjectReference(path: project.path, name: project.name)
            return seen.insert(normalized.path).inserted ? normalized : nil
        }.prefix(maxCount).map { $0 }
    }

    private func write(_ projects: [ProjectReference]) {
        if let encoded = try? JSONEncoder().encode(projects) {
            defaults.set(encoded, forKey: key)
        }
    }
}
