import SwiftUI

/// Inline status line for label reads and writes. It names a restriction
/// without asking for credentials and offers retry only when another attempt
/// can succeed.
struct IssueLabelStatusView: View {
    let text: String
    let systemImage: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: systemImage)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button("Try Again", action: retry)
                    .workbenchGhost()
            }
        }
    }
}

/// Per-issue label menu. The row itself still opens GitHub; this control lists
/// every repository label with a checkmark for the applied ones, so keyboard
/// and VoiceOver can change one label at a time.
struct IssueLabelMenu: View {
    let issue: GitHubIssue
    let labels: [GitHubIssueLabel]
    let canEdit: Bool
    let isPending: Bool
    let isEnabled: Bool
    let onSet: (GitHubIssueLabel, Bool) -> Void

    var body: some View {
        if canEdit, !labels.isEmpty {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                    .accessibilityLabel("Updating labels for issue \(issue.number)")
            } else {
                Menu {
                    ForEach(labels, id: \.name) { label in
                        Toggle(
                            label.name,
                            isOn: Binding(
                                get: { issue.labels.contains { $0.name == label.name } },
                                set: { isOn in onSet(label, isOn) }
                            )
                        )
                    }
                } label: {
                    Image(systemName: "tag")
                        .font(WorkbenchTypography.body)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                .contentShape(Rectangle())
                .disabled(!isEnabled)
                .help("Edit labels for issue \(issue.number)")
                .accessibilityLabel("Edit labels for issue \(issue.number), \(issue.title)")
                .accessibilityHint("Choose labels to apply or remove")
            }
        }
    }
}

/// Copy for label failures and restrictions. A permission problem stays
/// distinct from a connection error, because only the latter can be retried.
enum IssueLabelMessages {
    static func mutation(_ error: GitHubIssueLabelError) -> String {
        switch error {
        case .notAuthenticated:
            "Sign in to GitHub in Settings to change labels."
        case .repositoryNotFound:
            "GitHub did not find this repository, or your account cannot access it."
        case .forbidden:
            "Your GitHub account cannot change labels in this repository. Ask a repository admin for write access."
        case .requestFailed:
            "Could not update labels. Check your connection and try again."
        }
    }

    static func list(_ error: GitHubIssueLabelError) -> String {
        switch error {
        case .notAuthenticated:
            "Sign in to GitHub in Settings to change labels."
        case .repositoryNotFound:
            "Could not load this repository's labels."
        case .forbidden:
            "Your GitHub account cannot change labels in this repository. Ask a repository admin for write access."
        case .requestFailed:
            "Could not load labels. Check your connection and try again."
        }
    }
}

#Preview("Issue Label Controls") {
    let issue = GitHubIssue(
        number: 42,
        title: "Consultar a lista de issues do projeto dentro do app",
        state: .open,
        authorLogin: "mourato",
        createdAt: Date(),
        updatedAt: Date(),
        labels: [GitHubIssueLabel(name: "bug", colorHex: "d73a4a", nodeID: "L_bug")],
        url: URL(fileURLWithPath: "/issues/42"),
        nodeID: "I_42"
    )
    let labels = [
        GitHubIssueLabel(name: "bug", colorHex: "d73a4a", nodeID: "L_bug"),
        GitHubIssueLabel(name: "enhancement", colorHex: "a2eeef", nodeID: "L_enh")
    ]

    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
        HStack {
            Text(issue.title)
                .font(WorkbenchTypography.body)
            Spacer()
            IssueLabelMenu(
                issue: issue,
                labels: labels,
                canEdit: true,
                isPending: false,
                isEnabled: true,
                onSet: { _, _ in }
            )
        }
        IssueLabelStatusView(
            text: IssueLabelMessages.mutation(.forbidden),
            systemImage: "exclamationmark.triangle",
            retry: nil
        )
        IssueLabelStatusView(
            text: "Labels are read-only in this repository. Your GitHub account can view them but not change them.",
            systemImage: "lock",
            retry: nil
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth)
    .padding()
}
