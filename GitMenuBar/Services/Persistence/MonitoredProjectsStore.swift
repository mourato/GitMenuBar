import Foundation

final class MonitoredProjectsStore {
    private let defaults: UserDefaults
    private let key: String
    private let seededKey: String
    private let maxCount: Int

    init(
        defaults: UserDefaults = .standard,
        key: String = AppPreferences.Keys.monitoredProjects,
        seededKey: String = AppPreferences.Keys.monitoredProjectsSeeded,
        maxCount: Int = 20
    ) {
        self.defaults = defaults
        self.key = key
        self.seededKey = seededKey
        self.maxCount = maxCount
    }

    func monitoredProjects() -> [ProjectReference] {
        guard let data = defaults.data(forKey: key),
              let projects = try? JSONDecoder().decode([ProjectReference].self, from: data)
        else { return [] }
        return normalized(projects)
    }

    func add(_ path: String, name: String? = nil) {
        upsert(path: path, name: name)
    }

    func upsert(path: String, name: String? = nil) {
        let normalizedPath = RecentProjectsStore.normalize(path)
        var projects = monitoredProjects()
        let existing = projects.first { $0.path == normalizedPath }
        projects.removeAll { $0.path == normalizedPath }
        projects.insert(ProjectReference(path: normalizedPath, name: name ?? existing?.name), at: 0)
        write(projects)
    }

    func remove(path: String) {
        let normalizedPath = RecentProjectsStore.normalize(path)
        write(monitoredProjects().filter { $0.path != normalizedPath })
    }

    func contains(path: String) -> Bool {
        monitoredProjects().contains { $0.path == RecentProjectsStore.normalize(path) }
    }

    func rename(path: String, name: String) {
        let normalizedPath = RecentProjectsStore.normalize(path)
        let projects = monitoredProjects().map { project in
            project.path == normalizedPath
                ? ProjectReference(path: project.path, name: name)
                : project
        }
        write(projects)
    }

    @discardableResult
    func seedIfNeeded(currentPath: String, recentProjects: [ProjectReference]) -> [ProjectReference] {
        guard !defaults.bool(forKey: seededKey) else { return monitoredProjects() }
        var projects = recentProjects
        if !currentPath.isEmpty {
            projects.insert(ProjectReference(path: currentPath), at: 0)
        }
        write(projects)
        defaults.set(true, forKey: seededKey)
        return monitoredProjects()
    }

    private func normalized(_ projects: [ProjectReference]) -> [ProjectReference] {
        var seen = Set<String>()
        return projects.compactMap { project in
            let normalized = ProjectReference(path: project.path, name: project.name)
            return seen.insert(normalized.path).inserted ? normalized : nil
        }.prefix(maxCount).map(\.self)
    }

    private func write(_ projects: [ProjectReference]) {
        guard let data = try? JSONEncoder().encode(normalized(projects)) else { return }
        defaults.set(data, forKey: key)
    }
}
