import SwiftUI

struct ProjectCleanupResultsView: View {
    let result: ProjectCleanupRunResult
    let onDismiss: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text("Cleanup Results")
                    .font(WorkbenchTypography.windowTitle)
                summary
            }

            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                    .workbenchGhost()
                Spacer(minLength: 0)
                Button("Dismiss", action: onDismiss)
                    .workbenchSecondary()
                    .keyboardShortcut(.cancelAction)
            }

            if result.projects.isEmpty {
                ContentUnavailableView(
                    "No Cleanup Results",
                    systemImage: "checkmark.circle",
                    description: Text("No cleanup changes were recorded.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                        ForEach(result.projects) { project in
                            projectResultView(project)
                        }
                    }
                }
            }
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(minWidth: 520, minHeight: 300)
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        HStack(spacing: WorkbenchMetrics.sectionSpacing) {
            summaryItem(result.completedCount, title: "completed", icon: "checkmark.circle.fill", color: .green)
            summaryItem(result.partialCount, title: "partial", icon: "exclamationmark.circle.fill", color: .orange)
            summaryItem(result.skippedCount, title: "skipped", icon: "minus.circle.fill", color: .secondary)
            summaryItem(result.failedCount, title: "failed", icon: "xmark.octagon.fill", color: .red)
            summaryItem(result.excludedCount, title: "excluded", icon: "nosign", color: .secondary)
        }
        .font(WorkbenchTypography.captionStrong)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryItem(_ count: Int, title: String, icon: String, color: Color) -> some View {
        Label("\(count) \(title)", systemImage: icon)
            .foregroundStyle(color)
    }

    private func projectResultView(_ project: ProjectCleanupProjectResult) -> some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.project.name)
                    .font(WorkbenchTypography.sectionLabel)

                Spacer(minLength: WorkbenchMetrics.compactSpacing)

                if project.exclusionReason != nil {
                    Label("Excluded", systemImage: "nosign")
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundStyle(.secondary)
                }
            }

            if let reason = project.exclusionReason {
                Text(reason)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if project.items.isEmpty {
                Text("No cleanup items recorded.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(project.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.microSpacing) {
                        Image(systemName: statusIcon(item.status))
                            .foregroundStyle(statusColor(item.status))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                            Text(item.unit?.title ?? item.target.title)
                                .font(WorkbenchTypography.captionStrong)
                            Text(statusDescription(item.status))
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(0.16),
            in: RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
        )
    }

    private func statusDescription(_ value: GitCleanupItemResultStatus) -> String {
        switch value {
        case .succeeded: "completed"
        case let .partiallySucceeded(reason): "partial — \(reason)"
        case let .skipped(reason): "skipped — \(reason)"
        case let .failed(reason): "failed — \(reason)"
        }
    }

    private func statusIcon(_ value: GitCleanupItemResultStatus) -> String {
        switch value {
        case .succeeded: "checkmark.circle.fill"
        case .partiallySucceeded: "exclamationmark.circle.fill"
        case .skipped: "minus.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func statusColor(_ value: GitCleanupItemResultStatus) -> Color {
        switch value {
        case .succeeded: .green
        case .partiallySucceeded: .orange
        case .skipped: .secondary
        case .failed: .red
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
