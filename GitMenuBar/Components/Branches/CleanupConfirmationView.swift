import SwiftUI

struct CleanupConfirmationView: View {
    let targets: [GitCleanupTarget]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var didReviewRisk = false

    private var localBranches: [GitCleanupTarget] {
        targets.filter {
            if case .localBranch = $0 {
                return true
            }
            return false
        }
    }

    private var worktrees: [GitCleanupTarget] {
        targets.filter {
            if case .worktree = $0 {
                return true
            }
            return false
        }
    }

    private var remoteBranches: [GitCleanupTarget] {
        targets.filter {
            if case .remoteBranch = $0 {
                return true
            }
            return false
        }
    }

    private var requiresRiskReview: Bool {
        !worktrees.isEmpty || !remoteBranches.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(requiresRiskReview && !didReviewRisk ? "Review Cleanup" : "Confirm Cleanup")
                .font(.headline.weight(.semibold))

            Text(summaryText)
                .font(MacChromeTypography.detail)
                .foregroundStyle(.secondary)

            if requiresRiskReview && !didReviewRisk {
                Label(
                    "Worktree directories will be removed from disk. Review the list before continuing.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(MacChromeTypography.caption)
                .foregroundStyle(.orange)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    targetSection("Local branches", targets: localBranches)
                    targetSection("Worktree directories", targets: worktrees)
                    targetSection("Remote branches", targets: remoteBranches)
                }
            }
            .frame(maxHeight: 260)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(
                    requiresRiskReview && !didReviewRisk ? "Review Worktree Removal" : "Confirm Cleanup",
                    action: confirmAction
                )
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .macPanelSurface(cornerRadius: MacChromeMetrics.largeCornerRadius, material: .regular)
        .accessibilityElement(children: .contain)
    }

    private var summaryText: String {
        "\(localBranches.count) local branch\(localBranches.count == 1 ? "" : "es"), "
            + "\(worktrees.count) worktree\(worktrees.count == 1 ? "" : "s"), "
            + "\(remoteBranches.count) remote branch\(remoteBranches.count == 1 ? "" : "es") selected."
    }

    private func targetSection(_ title: String, targets: [GitCleanupTarget]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) (\(targets.count))")
                .font(MacChromeTypography.sectionLabel)
                .foregroundStyle(.secondary)
            if targets.isEmpty {
                Text("None selected")
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(targets) { target in
                    Label(target.title, systemImage: icon(for: target))
                        .font(MacChromeTypography.caption)
                        .lineLimit(2)
                }
            }
        }
    }

    private func icon(for target: GitCleanupTarget) -> String {
        switch target {
        case .localBranch:
            return "arrow.triangle.branch"
        case .worktree:
            return "folder"
        case .remoteBranch:
            return "icloud"
        }
    }

    private func confirmAction() {
        if requiresRiskReview, !didReviewRisk {
            didReviewRisk = true
        } else {
            onConfirm()
        }
    }
}

#Preview("Cleanup Confirmation") {
    CleanupConfirmationView(
        targets: [
            .localBranch(
                GitBranchCleanupInfo(
                    reference: GitBranchReference(name: "feature/merged", headHash: "1234", isRemote: false),
                    status: .mergedIntoDefault,
                    worktreePath: nil
                )
            ),
            .worktree(
                GitWorktreeCleanupInfo(
                    worktree: GitWorktreeInfo(
                        path: "/Users/example/feature-ui",
                        headHash: "5678",
                        branchName: "feature/ui",
                        workingTreeState: .clean
                    ),
                    status: .eligible
                )
            )
        ],
        onCancel: {},
        onConfirm: {}
    )
}
