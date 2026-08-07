import SwiftUI

struct ProjectCleanupResultsView: View {
    let result: ProjectCleanupRunResult
    let onDismiss: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            Text("Cleanup Results").font(.headline)
            Text("\(result.completedCount) completed · \(result.partialCount) partial · \(result.skippedCount) skipped · \(result.failedCount) failed · \(result.excludedCount) excluded")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                Button("Dismiss", action: onDismiss)
            }
            ForEach(result.projects) { project in
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.project.name).font(.subheadline.weight(.semibold))
                    if let reason = project.exclusionReason {
                        Text("Excluded: \(reason)").foregroundStyle(.secondary)
                    }
                    ForEach(project.items) { item in
                        Text("\(item.unit?.title ?? item.target.title): \(status(item.status))").font(.caption)
                    }
                }
            }
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .accessibilityElement(children: .contain)
    }

    private func status(_ value: GitCleanupItemResultStatus) -> String {
        switch value {
        case .succeeded: "completed"
        case let .partiallySucceeded(reason): "partial — \(reason)"
        case let .skipped(reason): "skipped — \(reason)"
        case let .failed(reason): "failed — \(reason)"
        }
    }
}

#Preview("Cleanup Results") {
    ProjectCleanupResultsView(result: ProjectCleanupRunResult(projects: [], affectedPaths: []), onDismiss: {}, onRefresh: {})
        .frame(width: 640)
}

#Preview("Partial Skipped Excluded Results") {
    ProjectCleanupResultsView(result: .previewResults, onDismiss: {}, onRefresh: {})
        .frame(width: 640)
}

private extension ProjectCleanupRunResult {
    static var previewResults: ProjectCleanupRunResult {
        let project = ProjectReference(path: "/tmp/results", name: "Results Project")
        let unit = GitCleanupUnit(
            repositoryIdentity: project.path,
            branch: GitBranchCleanupInfo(reference: GitBranchReference(name: "feature/cleanup", headHash: "hash", isRemote: false), status: .mergedIntoDefault, worktreePath: nil),
            worktree: nil
        )
        let items = [
            GitCleanupItemResult(unit: unit, status: .partiallySucceeded(reason: "Branch kept")),
            GitCleanupItemResult(unit: unit, status: .skipped(reason: "Stale state")),
            GitCleanupItemResult(unit: unit, status: .failed(reason: "Locked"))
        ]
        return ProjectCleanupRunResult(
            projects: [
                ProjectCleanupProjectResult(project: project, items: items, exclusionReason: nil),
                ProjectCleanupProjectResult(project: ProjectReference(path: "/tmp/unavailable", name: "Unavailable Project"), items: [], exclusionReason: "Repository unavailable.")
            ],
            affectedPaths: []
        )
    }
}
