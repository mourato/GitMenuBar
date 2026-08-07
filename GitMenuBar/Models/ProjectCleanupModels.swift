import Foundation

enum ProjectCleanupLoadState: Equatable {
    case idle
    case loading(completed: Int, total: Int)
    case loaded
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

enum ProjectCleanupAnalysisResult {
    case success(GitCleanupAnalysis)
    case failure(String)
}

struct ProjectCleanupRow: Identifiable {
    let project: ProjectReference
    let repositoryIdentity: String?
    let isCanonical: Bool
    let isShared: Bool
    let snapshot: GitWorktreeSnapshot?
    let unavailableReason: String?

    var id: String {
        project.path
    }

    var units: [GitCleanupUnit] {
        isCanonical ? snapshot?.cleanupUnits ?? [] : []
    }

    var branchCount: Int {
        units.count
    }

    var worktreeCount: Int {
        units.filter(\.isPaired).count
    }

    var isUnavailable: Bool {
        unavailableReason != nil
    }

    static func projectRows(
        projects: [ProjectReference],
        analyses: [String: ProjectCleanupAnalysisResult]
    ) -> [ProjectCleanupRow] {
        let successful = analyses.compactMap { path, result -> (String, GitCleanupAnalysis)? in
            guard case let .success(analysis) = result else { return nil }
            return (path, analysis)
        }
        let grouped = Dictionary(grouping: successful, by: { $0.1.repositoryIdentity })
        let canonicalPaths: [String: String] = Dictionary(uniqueKeysWithValues: grouped.compactMap { identity, entries in
            let mainPath = entries
                .flatMap(\.1.snapshot.worktrees)
                .first(where: { $0.worktree.isMainWorktree })
                .map { GitRepositoryContext.normalizedPath($0.worktree.path) }
            let canonical = entries.map(\.0).first(where: { $0 == mainPath }) ?? entries.map(\.0).sorted().first
            guard let canonical else { return nil }
            return (identity, canonical)
        })

        return projects.map { project in
            guard let result = analyses[project.path] else {
                return ProjectCleanupRow(project: project, repositoryIdentity: nil, isCanonical: false, isShared: false, snapshot: nil, unavailableReason: "Analysis was not completed.")
            }
            switch result {
            case let .failure(reason):
                return ProjectCleanupRow(project: project, repositoryIdentity: nil, isCanonical: false, isShared: false, snapshot: nil, unavailableReason: reason)
            case let .success(analysis):
                let isCanonical = canonicalPaths[analysis.repositoryIdentity] == project.path
                return ProjectCleanupRow(project: project, repositoryIdentity: analysis.repositoryIdentity, isCanonical: isCanonical, isShared: !isCanonical, snapshot: analysis.snapshot, unavailableReason: nil)
            }
        }
    }
}

struct ProjectCleanupReview: Identifiable {
    let rows: [ProjectCleanupRow]
    let excludedProjects: [ProjectCleanupProjectResult]
    var id: String {
        rows.map(\.id).joined(separator: "|")
    }

    var units: [GitCleanupUnit] {
        rows.flatMap(\.units)
    }

    var branchCount: Int {
        units.count
    }

    var worktreeCount: Int {
        units.filter(\.isPaired).count
    }
}

struct ProjectCleanupProjectResult: Identifiable {
    let project: ProjectReference
    let items: [GitCleanupItemResult]
    let exclusionReason: String?
    var id: String {
        project.path
    }
}

struct ProjectCleanupRunResult: Identifiable {
    let projects: [ProjectCleanupProjectResult]
    let affectedPaths: Set<String>

    var id: String {
        projects.map(\.id).joined(separator: "|")
    }

    var completedCount: Int {
        projects.flatMap(\.items).filter { $0.status == .succeeded }.count
    }

    var partialCount: Int {
        projects.flatMap(\.items).filter {
            if case .partiallySucceeded = $0.status {
                return true
            }; return false
        }.count
    }

    var skippedCount: Int {
        projects.flatMap(\.items).filter {
            if case .skipped = $0.status {
                return true
            }; return false
        }.count
    }

    var failedCount: Int {
        projects.flatMap(\.items).filter {
            if case .failed = $0.status {
                return true
            }; return false
        }.count
    }

    var excludedCount: Int {
        projects.filter { $0.exclusionReason != nil }.count
    }
}
