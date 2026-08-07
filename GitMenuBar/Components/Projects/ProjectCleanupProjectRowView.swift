import SwiftUI

struct ProjectCleanupProjectRowView: View {
    let row: ProjectCleanupRow
    let isSelected: Bool
    let isRunning: Bool
    let onToggle: () -> Void
    let onInspect: () -> Void
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel("Select \(row.project.name)")
            .disabled(!row.isCanonical || row.units.isEmpty || isRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.project.name).font(.headline)
                Text(row.project.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(statusText).font(.caption).foregroundStyle(row.isUnavailable ? .red : .secondary)
            }
            Spacer(minLength: 0)
            Button(action: onInspect) {
                Image(systemName: "eye")
            }
            .workbenchIcon()
            .accessibilityLabel("View safe cleanup candidates for \(row.project.name)")
            .accessibilityHint("Shows local branches and worktrees merged into the default branch.")
            .disabled(isRunning)
            if row.isCanonical, !row.units.isEmpty {
                Button("Clean \(row.project.name)", action: onClean)
                    .disabled(isRunning)
                    .accessibilityHint("Reviews safe cleanup for this project.")
            }
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        if let reason = row.unavailableReason {
            return "Unavailable: \(reason)"
        }
        if row.isShared {
            return "Shared repository"
        }
        if row.units.isEmpty {
            return "No safe cleanup candidates"
        }
        return "\(row.branchCount) branches · \(row.worktreeCount) worktrees"
    }
}

#Preview("Cleanup Row") {
    ProjectCleanupProjectRowView(row: ProjectCleanupRow(project: ProjectReference(path: "/tmp/example"), repositoryIdentity: nil, isCanonical: false, isShared: false, snapshot: nil, unavailableReason: "Repository unavailable."), isSelected: false, isRunning: false, onToggle: {}, onInspect: {}, onClean: {})
        .frame(width: 640)
}

#Preview("Shared Cleanup Row") {
    ProjectCleanupProjectRowView(row: ProjectCleanupRow(project: ProjectReference(path: "/tmp/shared"), repositoryIdentity: "/tmp/repository", isCanonical: false, isShared: true, snapshot: nil, unavailableReason: nil), isSelected: false, isRunning: false, onToggle: {}, onInspect: {}, onClean: {})
        .frame(width: 640)
}

#Preview("Selected Cleanup Row") {
    ProjectCleanupProjectRowView(row: .previewEligible, isSelected: true, isRunning: false, onToggle: {}, onInspect: {}, onClean: {})
        .frame(width: 640)
}

#Preview("Zero Candidate Row") {
    ProjectCleanupProjectRowView(row: ProjectCleanupRow(project: ProjectReference(path: "/tmp/empty"), repositoryIdentity: "/tmp/empty", isCanonical: true, isShared: false, snapshot: nil, unavailableReason: nil), isSelected: false, isRunning: false, onToggle: {}, onInspect: {}, onClean: {})
        .frame(width: 640)
}

extension ProjectCleanupRow {
    static var previewEligible: ProjectCleanupRow {
        let project = ProjectReference(path: "/tmp/selected", name: "Selected")
        let unit = GitCleanupUnit(
            repositoryIdentity: project.path,
            branch: GitBranchCleanupInfo(reference: GitBranchReference(name: "feature/cleanup", headHash: "hash", isRemote: false), status: .mergedIntoDefault, worktreePath: nil),
            worktree: nil
        )
        let snapshot = GitWorktreeSnapshot(repositoryPath: project.path, defaultBranchName: "main", defaultBranchRef: "refs/heads/main", analysisDescription: "preview", worktrees: [], branches: [], repositoryIdentity: project.path, cleanupUnits: [unit])
        return ProjectCleanupRow(project: project, repositoryIdentity: project.path, isCanonical: true, isShared: false, snapshot: snapshot, unavailableReason: nil)
    }
}
