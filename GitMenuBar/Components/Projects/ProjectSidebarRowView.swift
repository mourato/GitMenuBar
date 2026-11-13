import AppKit
import SwiftUI

/// The widest badge text the visible sidebar shows in each GitHub total column.
/// Every row reserves the same column width, while a column with no totals
/// disappears instead of holding an empty slot.
struct ProjectSidebarCountColumns: Equatable {
    let issues: String?
    let pullRequests: String?

    static func guides(for snapshots: [ProjectStatusSnapshot]) -> Self {
        Self(
            issues: widestText(snapshots.compactMap(\.openIssueBadge)),
            pullRequests: widestText(snapshots.compactMap(\.openPullRequestBadge))
        )
    }

    private static func widestText(_ badges: [GitHubOpenCountBadge]) -> String? {
        // Ranking only: the hidden guide view owns the actual column width, so
        // a near-tie between two strings cannot change the rendered size.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        return Set(badges.map(\.text)).max {
            ($0 as NSString).size(withAttributes: [.font: font]).width
                < ($1 as NSString).size(withAttributes: [.font: font]).width
        }
    }
}

/// One Projects sidebar row. GitHub totals sit in aligned Issues → Pull Requests
/// columns so names and counts line up across rows. When the row is narrower than
/// the name column's minimum plus both columns, the totals hide instead of
/// squeezing the name; VoiceOver still reads the totals from the row label.
struct ProjectSidebarRowView: View {
    let snapshot: ProjectStatusSnapshot
    let agentActivities: [AgentProjectActivity]
    let showsAgentActivity: Bool
    let countColumns: ProjectSidebarCountColumns

    var body: some View {
        ViewThatFits(in: .horizontal) {
            rowContent(showsOpenCountBadges: true)
            rowContent(showsOpenCountBadges: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func rowContent(showsOpenCountBadges: Bool) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.project.name)
                    .font(WorkbenchTypography.projectName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(snapshot.statusSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(
                minWidth: 0,
                idealWidth: WorkbenchMetrics.projectsRowTextMinimumWidth,
                maxWidth: .infinity,
                alignment: .leading
            )

            HStack(spacing: WorkbenchMetrics.microSpacing) {
                if showsAgentActivity, !agentActivities.isEmpty {
                    HStack(spacing: WorkbenchMetrics.microSpacing) {
                        ForEach(agentActivities) { activity in
                            AgentBadgeIconView(activity: activity)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                if snapshot.hasWorkingTreeChanges {
                    changeCountBadge
                }

                if showsOpenCountBadges {
                    openCountBadges
                }
            }
            .layoutPriority(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var dotColor: Color {
        guard snapshot.classification != .clean else {
            return .green
        }
        switch snapshot.severity {
        case .divergedOrBehind:
            return .red
        case .uncommittedChanges:
            return .orange
        case .unmergedOnly, .none:
            return .secondary
        }
    }

    private var changeCountBadge: some View {
        let count = snapshot.stagedCount + snapshot.unstagedCount + snapshot.untrackedCount
        return Text("\(count)")
            .sidebarCountChip()
    }

    /// Both columns stay in place whenever either total exists, so a pull request
    /// alone keeps the pull-request column instead of taking the issues column.
    @ViewBuilder
    private var openCountBadges: some View {
        if countColumns.issues != nil || countColumns.pullRequests != nil {
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                if let guide = countColumns.issues {
                    openCountSlot(snapshot.openIssueBadge, role: .issues, guide: guide)
                }
                if let guide = countColumns.pullRequests {
                    openCountSlot(snapshot.openPullRequestBadge, role: .pullRequests, guide: guide)
                }
            }
        }
    }

    /// The hidden guide is the widest badge in this column, so every row
    /// reserves the same width without storing measured geometry.
    private func openCountSlot(
        _ badge: GitHubOpenCountBadge?,
        role: GitHubCountRole,
        guide: String
    ) -> some View {
        ZStack(alignment: .leading) {
            openCountLabel(role: role, text: guide)
                .hidden()
                .accessibilityHidden(true)
            if let badge {
                openCountLabel(role: role, text: badge.text)
                    .help(badge.accessibilityDescription(singularNoun: role.noun))
            }
        }
        .font(WorkbenchTypography.caption)
        .accessibilityHidden(true)
    }

    private func openCountLabel(role: GitHubCountRole, text: String) -> some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            Image(systemName: role.symbol)
                .foregroundStyle(role.marker)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    var accessibilityLabel: String {
        var parts = [snapshot.project.name, snapshot.statusSummary]
        if showsAgentActivity, !agentActivities.isEmpty {
            parts.append(agentActivities.map(\.accessibilityDescription).joined(separator: ", "))
        }
        if snapshot.hasWorkingTreeChanges {
            parts.append(
                "\(snapshot.stagedCount) staged, \(snapshot.unstagedCount) unstaged, "
                    + "\(snapshot.untrackedCount) untracked"
            )
        }
        if let issues = snapshot.openIssueBadge {
            parts.append(issues.accessibilityDescription(singularNoun: "issue"))
        }
        if let pullRequests = snapshot.openPullRequestBadge {
            parts.append(pullRequests.accessibilityDescription(singularNoun: "pull request"))
        }
        if let error = snapshot.lastErrorDescription {
            parts.append(error)
        }
        return parts.joined(separator: ", ")
    }
}

/// Icons and colors for the two GitHub totals, kept in one place so the marker
/// roles match the repository overview strip.
private enum GitHubCountRole {
    case issues
    case pullRequests

    var symbol: String {
        switch self {
        case .issues: "smallcircle.filled.circle"
        case .pullRequests: "arrow.triangle.pull"
        }
    }

    var noun: String {
        switch self {
        case .issues: "issue"
        case .pullRequests: "pull request"
        }
    }

    var marker: Color {
        switch self {
        case .issues: WorkbenchPalette.issueMarker()
        case .pullRequests: WorkbenchPalette.pullRequestMarker()
        }
    }
}

/// Shared capsule for the local change count. GitHub totals keep plain neutral
/// numbers beside their colored marker instead.
private struct SidebarCountChipStyle: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .font(WorkbenchTypography.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, WorkbenchMetrics.chipSpacing)
            .padding(.vertical, WorkbenchMetrics.headerVerticalPadding)
            .background(
                Capsule()
                    .fill(WorkbenchPalette.hoverFill())
            )
            .overlay(
                Capsule()
                    .strokeBorder(WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast), lineWidth: 1)
            )
    }
}

private extension View {
    func sidebarCountChip() -> some View {
        modifier(SidebarCountChipStyle())
    }
}

// MARK: - Previews

private enum ProjectSidebarRowPreviewData {
    static func snapshot(
        name: String,
        branch: String = "main",
        aheadCount: Int = 0,
        unpushedBranchCount: Int = 0,
        unmergedBranchCount: Int = 0,
        stagedCount: Int = 0,
        openIssueCount: Int? = 0,
        openPullRequestCount: Int? = 0,
        unavailableReason: GitHubStatusUnavailableReason? = nil,
        pullRequests: [GitHubPullRequestSummary] = []
    ) -> ProjectStatusSnapshot {
        ProjectStatusSnapshot(
            project: ProjectReference(path: "/tmp/\(name)", name: name),
            branchName: branch,
            isDetachedHead: false,
            stagedCount: stagedCount,
            unstagedCount: 0,
            untrackedCount: 0,
            lineDiff: .zero,
            aheadCount: aheadCount,
            behindCount: 0,
            hasUpstream: true,
            lastRefreshedAt: nil,
            lastErrorDescription: nil,
            branchesWithoutUpstreamCount: 0,
            unpushedBranchCount: unpushedBranchCount,
            unmergedBranchCount: unmergedBranchCount,
            stashCount: 0,
            lastActivityAt: nil,
            gitHubStatus: GitHubProjectStatus(
                pullRequests: pullRequests,
                openPullRequestCount: openPullRequestCount,
                openIssueCount: openIssueCount,
                unavailableReason: unavailableReason
            )
        )
    }

    static let rows: [ProjectStatusSnapshot] = [
        snapshot(name: "sample-app", unmergedBranchCount: 1, openIssueCount: 9, openPullRequestCount: 2),
        snapshot(name: "notes", unmergedBranchCount: 1, openIssueCount: 0, openPullRequestCount: 1),
        snapshot(name: "budget", unmergedBranchCount: 18, openIssueCount: 6, openPullRequestCount: 0),
        snapshot(name: "website", aheadCount: 2, openIssueCount: 0, openPullRequestCount: 2),
        snapshot(name: "tools", unmergedBranchCount: 8, stagedCount: 3, openIssueCount: 6, openPullRequestCount: 1),
        snapshot(name: "git-client", unmergedBranchCount: 3, openIssueCount: 4, openPullRequestCount: nil),
        snapshot(name: "design-kit", unmergedBranchCount: 1, openIssueCount: 0, openPullRequestCount: 0),
        snapshot(name: "api-service", unmergedBranchCount: 2, openIssueCount: 0, openPullRequestCount: 2),
        snapshot(name: "reader", unmergedBranchCount: 4, openIssueCount: 1284, openPullRequestCount: 2),
        snapshot(
            name: "a-project-with-a-name-long-enough-to-truncate",
            unmergedBranchCount: 52,
            openIssueCount: 12,
            openPullRequestCount: 34
        ),
        snapshot(
            name: "offline-counts",
            unmergedBranchCount: 2,
            openIssueCount: nil,
            openPullRequestCount: nil,
            unavailableReason: .commandFailed
        ),
        snapshot(
            name: "local-only",
            unmergedBranchCount: 3,
            openIssueCount: nil,
            openPullRequestCount: nil,
            unavailableReason: .notGitHubRemote
        )
    ]
}

private struct ProjectSidebarRowPreviewList: View {
    @State private var selection: String? = ProjectSidebarRowPreviewData.rows[0].project.path

    let width: CGFloat
    var body: some View {
        List(selection: $selection) {
            ForEach(ProjectSidebarRowPreviewData.rows) { snapshot in
                ProjectSidebarRowView(
                    snapshot: snapshot,
                    agentActivities: [],
                    showsAgentActivity: true,
                    countColumns: .guides(for: ProjectSidebarRowPreviewData.rows)
                )
                .tag(snapshot.project.path)
            }
        }
        .listStyle(.sidebar)
        .environment(\.controlActiveState, .inactive)
        .frame(width: width, height: 620)
    }
}

#Preview("Project Rows — Minimum Width") {
    ProjectSidebarRowPreviewList(width: WorkbenchMetrics.projectsMinimumWidth)
}

#Preview("Project Rows — Maximum Width") {
    ProjectSidebarRowPreviewList(width: WorkbenchMetrics.projectsMaximumWidth)
}

#Preview("Project Rows — Minimum Width, Dark") {
    ProjectSidebarRowPreviewList(width: WorkbenchMetrics.projectsMinimumWidth)
        .preferredColorScheme(.dark)
}
