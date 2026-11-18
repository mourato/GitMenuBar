import SwiftUI

// Presentation model for the repository overview strip. The view owns the
// values; these types keep the order, groups, and emphasis readable.

enum RepositoryOverviewMetricDensity: Equatable {
    case wide
    case medium
    case compact
}

/// Local Git metrics lead the strip; the GitHub metrics follow after the group
/// divider, matching the Projects sidebar's Issues → Pull Requests order.
enum RepositoryOverviewMetricGroup {
    case localGit
    case github
}

/// The side panel a metric opens. GitHub metrics open on GitHub instead,
/// so those cells never own the panel's active state.
enum RepositoryOverviewMetricPanel {
    case changes
    case branches
    case stashes
}

enum RepositoryOverviewMetricEmphasis {
    case strong
    case quiet
}

enum RepositoryOverviewMetricMarker {
    case issue
    case pullRequest

    var color: Color {
        switch self {
        case .issue: WorkbenchPalette.issueMarker()
        case .pullRequest: WorkbenchPalette.pullRequestMarker()
        }
    }
}

struct RepositoryOverviewMetricDefinition {
    let title: String
    let shortTitle: String
    let symbol: LucideIconName
    let group: RepositoryOverviewMetricGroup
    let marker: RepositoryOverviewMetricMarker?
    let accessibilityHint: String

    init(
        _ title: String,
        _ shortTitle: String,
        _ symbol: LucideIconName,
        group: RepositoryOverviewMetricGroup = .localGit,
        marker: RepositoryOverviewMetricMarker? = nil,
        _ accessibilityHint: String
    ) {
        self.title = title
        self.shortTitle = shortTitle
        self.symbol = symbol
        self.group = group
        self.marker = marker
        self.accessibilityHint = accessibilityHint
    }

    static let changes = Self("Changes", "Changes", .diff, "Opens Changes in the side panel")
    static let branches = Self("Branches", "Branches", .gitBranch, "Opens Branches in the side panel")
    static let stashes = Self("Stashes", "Stashes", .archive, "Opens Stashes in the side panel")
    static let issues = Self(
        "Issues",
        "Issues",
        .circleDot,
        group: .github,
        marker: .issue,
        "Opens issues on GitHub"
    )

    static let pullRequests = Self(
        "Pull Requests",
        "PRs",
        .gitPullRequest,
        group: .github,
        marker: .pullRequest,
        "Opens pull requests on GitHub"
    )
}

struct RepositoryOverviewMetricPresentation {
    let value: String
    let qualifier: String
    let accessibilityValue: String
    let state: RepositoryMetricState<Int>
    let isError: Bool
}

struct RepositoryOverviewMetric {
    let title: String
    let shortTitle: String
    let symbol: LucideIconName
    let group: RepositoryOverviewMetricGroup
    let marker: RepositoryOverviewMetricMarker?
    let value: String
    let qualifier: String
    let state: RepositoryMetricState<Int>
    let emphasis: RepositoryOverviewMetricEmphasis
    let isError: Bool
    let panel: RepositoryOverviewMetricPanel?
    let accessibilityValue: String
    let helpText: String
    let accessibilityHint: String
    let action: (() -> Void)?
}
