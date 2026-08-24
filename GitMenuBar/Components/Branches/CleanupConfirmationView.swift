import SwiftUI

struct CleanupConfirmationView: View {
    let units: [GitCleanupUnit]
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var didReviewRisk = false

    private var branchOnly: [GitCleanupUnit] {
        units.filter { !$0.isPaired }
    }

    private var paired: [GitCleanupUnit] {
        units.filter(\.isPaired)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(didReviewRisk || paired.isEmpty ? "Confirm Cleanup" : "Review Cleanup")
                .font(.headline.weight(.semibold))
            Text("\(branchOnly.count) branch-only unit\(branchOnly.count == 1 ? "" : "s"), \(paired.count) paired unit\(paired.count == 1 ? "" : "s") selected.")
                .font(WorkbenchTypography.detail)
                .foregroundStyle(.secondary)
            if !paired.isEmpty, !didReviewRisk {
                Label("Paired worktree directories will be removed before their branches.", systemImage: "exclamationmark.triangle.fill")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("Branch-only cleanup", branchOnly)
                    section("Paired worktree and branch cleanup", paired)
                }
            }
            .frame(maxHeight: 260)
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(didReviewRisk || paired.isEmpty ? "Confirm Cleanup" : "Review Worktree Removal") {
                    if paired.isEmpty || didReviewRisk {
                        onConfirm()
                    } else {
                        didReviewRisk = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.largeCornerRadius, material: .regular)
        .accessibilityElement(children: .contain)
    }

    private func section(_ title: String, _ units: [GitCleanupUnit]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) (\(units.count))")
                .font(WorkbenchTypography.sectionLabel)
                .foregroundStyle(.secondary)
            if units.isEmpty {
                Text("None selected")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(units) { unit in
                    Label(unit.title, systemImage: unit.isPaired ? "folder" : "arrow.triangle.branch")
                        .font(WorkbenchTypography.caption)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct CleanupProgressView: View {
    let progress: GitCleanupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            HStack {
                Text("Cleaning \(progress.projectName ?? "project")")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(progress.completed) of \(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(progress.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cleanup progress")
        .accessibilityValue("\(progress.completed) of \(progress.total). \(progress.projectName ?? "Project"). \(progress.detail)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Cleanup Confirmation") {
    let branch = GitBranchCleanupInfo(
        reference: GitBranchReference(name: "feature/merged", headHash: "1234", isRemote: false),
        status: .mergedIntoDefault,
        worktreePath: nil
    )
    CleanupConfirmationView(
        units: [GitCleanupUnit(repositoryIdentity: "/repo", branch: branch, worktree: nil)],
        onCancel: {},
        onConfirm: {}
    )
}

#Preview("Cleanup Progress") {
    CleanupProgressView(progress: GitCleanupProgress(
        completed: 12,
        total: 40,
        projectName: "Example Project",
        detail: "Removing worktree /tmp/example-feature"
    ))
    .frame(width: 460)
}
