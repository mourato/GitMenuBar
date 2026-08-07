import SwiftUI

struct ProjectCleanupCandidatesView: View {
    let row: ProjectCleanupRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.groupSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    Text("Safe Cleanup Candidates")
                        .font(.title2.weight(.semibold))
                    Text(row.project.name)
                        .font(.headline)
                    Text("Only local branches merged into \(defaultBranchName) are shown. Linked worktrees are removed before their branches.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: WorkbenchMetrics.compactSpacing)
                Button("Close", role: .cancel) { dismiss() }
            }

            if row.units.isEmpty {
                ContentUnavailableView(
                    "No Safe Cleanup Candidates",
                    systemImage: "checkmark.shield",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                        ForEach(row.units) { unit in
                            candidateRow(unit)
                        }
                    }
                }
            }
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(minWidth: 520, minHeight: 320)
        .accessibilityElement(children: .contain)
    }

    private var defaultBranchName: String {
        row.snapshot?.defaultBranchName ?? "the default branch"
    }

    private var emptyDescription: String {
        if let reason = row.unavailableReason {
            return reason
        }
        if row.isShared {
            return "This project is a linked worktree. Review candidates from the canonical project."
        }
        return "No branches or worktrees are safe to remove."
    }

    private func candidateRow(_ unit: GitCleanupUnit) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Label(unit.branch.reference.name, systemImage: "arrow.triangle.branch")
                .font(.body.weight(.medium))
            Text("Merged into \(defaultBranchName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let worktree = unit.worktree {
                Label(worktree.worktree.path, systemImage: "square.stack.3d.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: unit))
    }

    private func accessibilityLabel(for unit: GitCleanupUnit) -> String {
        if let worktree = unit.worktree {
            return "Branch \(unit.branch.reference.name), merged into \(defaultBranchName), worktree \(worktree.worktree.path)"
        }
        return "Branch \(unit.branch.reference.name), merged into \(defaultBranchName)"
    }
}

#Preview("Safe Cleanup Candidates") {
    ProjectCleanupCandidatesView(row: .previewEligible)
}

#Preview("No Safe Cleanup Candidates") {
    ProjectCleanupCandidatesView(
        row: ProjectCleanupRow(
            project: ProjectReference(path: "/tmp/empty", name: "Empty Project"),
            repositoryIdentity: "/tmp/empty",
            isCanonical: true,
            isShared: false,
            snapshot: nil,
            unavailableReason: nil
        )
    )
}
