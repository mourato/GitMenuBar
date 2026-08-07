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
