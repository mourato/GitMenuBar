import SwiftUI

struct ProjectCleanupProjectRowView: View {
    let row: ProjectCleanupRow
    let isSelected: Bool
    let isRunning: Bool
    let onToggle: () -> Void
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Toggle("Select \(row.project.name)", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .disabled(!row.isCanonical || row.units.isEmpty || isRunning)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.project.name).font(.headline)
                Text(row.project.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(statusText).font(.caption).foregroundStyle(row.isUnavailable ? .red : .secondary)
            }
            Spacer(minLength: 0)
            if row.isCanonical, !row.units.isEmpty {
                Button("Clean", action: onClean)
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
    ProjectCleanupProjectRowView(row: ProjectCleanupRow(project: ProjectReference(path: "/tmp/example"), repositoryIdentity: nil, isCanonical: false, isShared: false, snapshot: nil, unavailableReason: "Repository unavailable."), isSelected: false, isRunning: false, onToggle: {}, onClean: {})
        .frame(width: 640)
}
