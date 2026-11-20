import AppKit
import SwiftUI

struct ProjectSidebarCountColumns: Equatable {
    let branches: String?
    let issues: String?
    let pullRequests: String?

    static func guides(for snapshots: [ProjectStatusSnapshot]) -> Self {
        Self(
            branches: widestText(snapshots.compactMap(\.unmergedBranchBadge).map { "\($0)" }),
            issues: widestText(snapshots.compactMap(\.openIssueBadge).map(\.text)),
            pullRequests: widestText(snapshots.compactMap(\.openPullRequestBadge).map(\.text))
        )
    }

    private static func widestText(_ texts: [String]) -> String? {
        let font = WorkbenchTypography.sidebarCountMeasurementFont
        return Set(texts).max {
            ($0 as NSString).size(withAttributes: [.font: font]).width
                < ($1 as NSString).size(withAttributes: [.font: font]).width
        }
    }
}

struct ProjectSidebarRowView: View {
    let snapshot: ProjectStatusSnapshot
    let agentActivities: [AgentProjectActivity]
    let showsAgentActivity: Bool
    let countColumns: ProjectSidebarCountColumns

    private static let dotSize: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                titleLine(showsCounts: true)
                titleLine(showsCounts: false)
            }
            summaryLine
                .padding(.leading, Self.dotSize + WorkbenchMetrics.compactSpacing)
        }
        .help(snapshot.statusSummary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func titleLine(showsCounts: Bool) -> some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            Circle()
                .fill(dotColor ?? .clear)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .fixedSize()

            HStack(spacing: WorkbenchMetrics.microSpacing) {
                Text(snapshot.project.name)
                    .font(WorkbenchTypography.projectName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if snapshot.gitHubStatus.isPrivate == true {
                    LucideIconView(name: .lock, size: WorkbenchMetrics.sidebarMicroIconSize)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .help("Private repository")
                }
            }
            .frame(
                minWidth: 0,
                idealWidth: WorkbenchMetrics.projectsRowTextMinimumWidth,
                maxWidth: .infinity,
                alignment: .leading
            )

            HStack(spacing: WorkbenchMetrics.sectionSpacing) {
                if showsAgentActivity, let lead = leadAgentActivity {
                    HStack(spacing: WorkbenchMetrics.microSpacing) {
                        AgentBadgeIconView(activity: lead, size: WorkbenchMetrics.sidebarInlineIconSize)
                        if agentActivities.count > 1 {
                            countText("+\(agentActivities.count - 1)")
                        }
                    }
                    .help(agentActivities.map(\.accessibilityDescription).joined(separator: "\n"))
                    .fixedSize(horizontal: true, vertical: false)
                }

                if showsCounts {
                    countSlots
                }
            }
            .layoutPriority(1)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var summaryLine: some View {
        let facts = snapshot.visibleFacts
        return ViewThatFits(in: .horizontal) {
            if facts.count > 1 {
                HStack(spacing: 0) {
                    factLabel(facts[0])
                    summaryText(ProjectStatusSnapshot.summaryFactSeparator)
                    factLabel(facts[1])
                }
                .fixedSize()
            }
            if let first = facts.first {
                factLabel(first)
            } else {
                summaryText(snapshot.idleSummary(now: Date()))
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private func factLabel(_ fact: ProjectSummaryFact) -> some View {
        switch fact {
        case let .behind(count):
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                summaryIcon(.arrowDown, tint: .secondary)
                summaryText("\(count) behind")
            }
        case .failingPullRequest:
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                summaryIcon(.x, tint: .red)
                summaryText(fact.spokenText)
            }
        case let .pullRequest(pullRequest) where pullRequest.checksState == .passed:
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                summaryText(["PR #\(pullRequest.number)", pullRequest.reviewSummary].compactMap(\.self).joined(separator: " "))
                summaryIcon(.check, tint: .green)
            }
        default:
            summaryText(fact.spokenText)
        }
    }

    private func summaryText(_ text: String) -> some View {
        Text(text)
            .font(WorkbenchTypography.detail)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func summaryIcon(_ name: LucideIconName, tint: Color) -> some View {
        LucideIconView(name: name, size: WorkbenchMetrics.sidebarMicroIconSize)
            .foregroundStyle(tint)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private var dotColor: Color? {
        switch snapshot.severity {
        case .critical: .red
        case .localWork: .orange
        case nil: nil
        }
    }

    private var leadAgentActivity: AgentProjectActivity? {
        AgentProjectActivity.lead(in: agentActivities)
    }

    private func countText(_ text: String) -> some View {
        Text(text)
            .font(WorkbenchTypography.sidebarCount)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
            .lineLimit(1)
    }

    @ViewBuilder
    private var countSlots: some View {
        if countColumns.branches != nil || countColumns.issues != nil || countColumns.pullRequests != nil {
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                if let guide = countColumns.branches {
                    countSlot(
                        text: snapshot.unmergedBranchBadge.map { "\($0)" },
                        help: snapshot.unmergedBranchBadge.map { ProjectSummaryFact.unmergedBranches($0).spokenText },
                        role: .branches,
                        guide: guide
                    )
                }
                if let guide = countColumns.issues {
                    countSlot(snapshot.openIssueBadge, role: .issues, guide: guide)
                }
                if let guide = countColumns.pullRequests {
                    countSlot(snapshot.openPullRequestBadge, role: .pullRequests, guide: guide)
                }
            }
        }
    }

    private func countSlot(_ badge: GitHubOpenCountBadge?, role: SidebarCountRole, guide: String) -> some View {
        countSlot(
            text: badge?.text,
            help: badge?.accessibilityDescription(singularNoun: role.noun),
            role: role,
            guide: guide
        )
    }

    private func countSlot(text: String?, help: String?, role: SidebarCountRole, guide: String) -> some View {
        ZStack(alignment: .leading) {
            countLabel(role: role, text: guide)
                .hidden()
            if let text {
                countLabel(role: role, text: text)
                    .help(help ?? "")
            }
        }
        .accessibilityHidden(true)
    }

    private func countLabel(role: SidebarCountRole, text: String) -> some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            LucideIconView(name: role.symbol, size: WorkbenchMetrics.sidebarMicroIconSize)
                .foregroundStyle(.tertiary)
            countText(text)
        }
    }

    var accessibilityLabel: String {
        var parts = [snapshot.project.name]
        if snapshot.gitHubStatus.isPrivate == true {
            parts.append("private repository")
        }
        parts.append(snapshot.statusSummary)
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

private enum SidebarCountRole {
    case branches
    case issues
    case pullRequests

    var symbol: LucideIconName {
        switch self {
        case .branches: .gitBranch
        case .issues: .circleDot
        case .pullRequests: .gitPullRequest
        }
    }

    var noun: String {
        switch self {
        case .branches: "unmerged branch"
        case .issues: "issue"
        case .pullRequests: "pull request"
        }
    }
}

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
        isPrivate: Bool? = nil,
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
                unavailableReason: unavailableReason,
                isPrivate: isPrivate
            )
        )
    }

    static let rows: [ProjectStatusSnapshot] = [
        snapshot(name: "sample-app", unmergedBranchCount: 1, openIssueCount: 9, openPullRequestCount: 2),
        snapshot(name: "notes", unmergedBranchCount: 1, openIssueCount: 0, openPullRequestCount: 1, isPrivate: true),
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
