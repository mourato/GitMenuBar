import SwiftUI

struct ProjectCleanupConfirmationView: View {
    let review: ProjectCleanupReview
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgedWorktreeRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            Text("Review Cleanup").font(.title2.weight(.semibold))
            Text("Clean \(review.branchCount) branches and \(review.worktreeCount) worktrees in \(review.rows.map(\.project.name).joined(separator: ", "))?")
            Text("This uses local Git state only. Linked worktree directories will be removed from disk.")
                .foregroundStyle(.secondary)
            if !review.excludedProjects.isEmpty {
                Text("Clean All will exclude \(review.excludedProjects.count) unavailable, shared, or empty project rows.")
                    .foregroundStyle(.secondary)
            }
            if review.worktreeCount > 0 {
                Toggle("I understand that worktree directories will be removed.", isOn: $acknowledgedWorktreeRemoval)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Confirm Cleanup") { onConfirm(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(review.worktreeCount > 0 && !acknowledgedWorktreeRemoval)
            }
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(minWidth: 460)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Cleanup Confirmation") {
    ProjectCleanupConfirmationView(review: ProjectCleanupReview(rows: [], excludedProjects: []), onConfirm: {})
}

#Preview("Paired Worktree Confirmation") {
    ProjectCleanupConfirmationView(review: .previewPaired, onConfirm: {})
}

private extension ProjectCleanupReview {
    static var previewPaired: ProjectCleanupReview {
        let project = ProjectReference(path: "/tmp/paired", name: "Paired Project")
        let worktreeInfo = GitWorktreeInfo(path: "/tmp/paired-worktree", headHash: "hash", branchName: "feature/cleanup", isMainWorktree: false, workingTreeState: .clean)
        let worktree = GitWorktreeCleanupInfo(worktree: worktreeInfo, status: .eligible)
        let unit = GitCleanupUnit(
            repositoryIdentity: project.path,
            branch: GitBranchCleanupInfo(reference: GitBranchReference(name: "feature/cleanup", headHash: "hash", isRemote: false), status: .checkedOutElsewhere(path: worktreeInfo.path), worktreePath: worktreeInfo.path),
            worktree: worktree
        )
        let snapshot = GitWorktreeSnapshot(repositoryPath: project.path, defaultBranchName: "main", defaultBranchRef: "refs/heads/main", analysisDescription: "preview", worktrees: [worktree], branches: [], repositoryIdentity: project.path, cleanupUnits: [unit])
        let row = ProjectCleanupRow(project: project, repositoryIdentity: project.path, isCanonical: true, isShared: false, snapshot: snapshot, unavailableReason: nil)
        return ProjectCleanupReview(rows: [row], excludedProjects: [])
    }
}
