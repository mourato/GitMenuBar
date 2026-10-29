import SwiftUI

struct ProjectCleanupConfirmationView: View {
    let review: ProjectCleanupReview
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgedWorktreeRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            Text("Review Cleanup")
                .font(.title2.weight(.semibold))
            Text("Clean \(review.branchCount) branches and \(review.worktreeCount) worktrees in \(review.rows.map(\.project.name).joined(separator: ", "))?")
                .font(WorkbenchTypography.detail)
            Text("This uses local Git state only. Linked worktree directories will be removed from disk.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
                    readySection
                    blockedSection
                }
            }
            .frame(maxHeight: 240)
            if review.worktreeCount > 0 {
                Toggle("I understand that worktree directories will be removed.", isOn: $acknowledgedWorktreeRemoval)
                    .font(WorkbenchTypography.detail)
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

    @ViewBuilder
    private var readySection: some View {
        if !review.rows.isEmpty {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                CleanupSectionHeader(title: "Ready", count: review.rows.count)
                ForEach(review.rows) { row in
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                        Text(row.project.name)
                            .font(WorkbenchTypography.detail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(row.branchCount) branches · \(row.worktreeCount) worktrees")
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var blockedSection: some View {
        if !review.excludedProjects.isEmpty {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                CleanupSectionHeader(title: "Blocked", count: review.excludedProjects.count)
                ForEach(review.excludedProjects) { project in
                    VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                        Text(project.project.name)
                            .font(WorkbenchTypography.detail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let reason = project.exclusionReason {
                            Text(reason)
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
                    .opacity(0.5)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

#Preview("Cleanup Confirmation") {
    ProjectCleanupConfirmationView(review: ProjectCleanupReview(rows: [], excludedProjects: []), onConfirm: {})
}

#Preview("Paired Worktree Confirmation") {
    ProjectCleanupConfirmationView(review: .previewPaired, onConfirm: {})
}

#Preview("Ready and Blocked Projects") {
    ProjectCleanupConfirmationView(review: .previewMixed, onConfirm: {})
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

    static var previewMixed: ProjectCleanupReview {
        let excluded = ProjectCleanupProjectResult(
            project: ProjectReference(path: "/tmp/offline", name: "Offline Project"),
            items: [],
            exclusionReason: "Repository unavailable."
        )
        return ProjectCleanupReview(rows: previewPaired.rows, excludedProjects: [excluded])
    }
}
