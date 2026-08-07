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
                        Text("\(item.target.title): \(status(item.status))").font(.caption)
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
