import SwiftUI

/// Calm empty state for a working tree with nothing to commit.
struct WorkingTreeCleanStateView: View {
    let lastCommitSubject: String?
    let lastCommitRelativeDate: String?
    let aheadCount: Int
    let onPush: () -> Void

    var body: some View {
        VStack(spacing: WorkbenchMetrics.compactSpacing) {
            VStack(spacing: WorkbenchMetrics.compactSpacing) {
                Image(systemName: "checkmark.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Everything committed")
                    .font(WorkbenchTypography.sectionLabel)

                if let lastCommitSummary {
                    Text(lastCommitSummary)
                        .font(WorkbenchTypography.detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            if aheadCount > 0 {
                Button(pushTitle, action: onPush)
                    .workbenchSecondary()
                    .frame(minHeight: WorkbenchMetrics.minimumHitTarget)
            }
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(maxWidth: .infinity)
    }

    private var lastCommitSummary: String? {
        guard let lastCommitSubject else { return nil }
        guard let lastCommitRelativeDate else { return "Last commit: \(lastCommitSubject)" }
        return "Last commit: \(lastCommitSubject), \(lastCommitRelativeDate)"
    }

    private var pushTitle: String {
        "Push \(aheadCount) \(aheadCount == 1 ? "commit" : "commits")"
    }
}

#Preview("Clean, Nothing to Push") {
    WorkingTreeCleanStateView(
        lastCommitSubject: "Add flat and tree views for working tree files",
        lastCommitRelativeDate: "2 hours ago",
        aheadCount: 0,
        onPush: {}
    )
    .frame(width: 360)
}

#Preview("Clean, Commits Ahead") {
    WorkingTreeCleanStateView(
        lastCommitSubject: "fix(cleanup): uncheck unmerged branches by default",
        lastCommitRelativeDate: "yesterday",
        aheadCount: 3,
        onPush: {}
    )
    .frame(width: 360)
}

#Preview("Clean, Single Commit Ahead, No Date") {
    WorkingTreeCleanStateView(
        lastCommitSubject: "Refactor branch list leading edge",
        lastCommitRelativeDate: nil,
        aheadCount: 1,
        onPush: {}
    )
    .frame(width: 360)
}

#Preview("Clean, No Commit Metadata") {
    WorkingTreeCleanStateView(
        lastCommitSubject: nil,
        lastCommitRelativeDate: nil,
        aheadCount: 0,
        onPush: {}
    )
    .frame(width: 360)
}
