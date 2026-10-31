import SwiftUI

struct RepositoryOverviewView: View {
    let overview: RepositoryOverviewSnapshot
    let onSelectSection: (MainMenuSidePanelSelection) -> Void
    let onOpenGitHubPage: (MainMenuGitHubDestination) -> Void
    let canOpenGitHubPage: Bool
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    var body: some View {
        ViewThatFits(in: .horizontal) {
            metricRow(density: .wide)
            metricRow(density: .medium)
            metricRow(density: .compact)
        }
        .frame(maxWidth: .infinity)
        .padding(WorkbenchMetrics.microSpacing)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            .quaternary.opacity(0.16),
            in: RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    WorkbenchPalette.neutralBorder(contrast: colorSchemeContrast),
                    lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
                )
                .allowsHitTesting(false)
        }
        .adaptiveMotion()
    }

    private func metricRow(density: RepositoryOverviewMetricDensity) -> some View {
        RepositoryOverviewMetricRowLayout(density: density) {
            ForEach(Array(metrics.enumerated()), id: \.element.title) { index, metric in
                RepositoryOverviewColumnView(
                    metric: metric,
                    density: density
                )

                if index < metrics.count - 1, density != .compact {
                    HStack(spacing: 0) { Divider().padding(.vertical, WorkbenchMetrics.microSpacing) }
                }
            }
        }
    }

    private var metrics: [RepositoryOverviewMetric] {
        let changes = changesPresentation
        let branches = branchesPresentation
        let stashes = stashesPresentation
        return [
            makeMetric(
                .changes,
                presentation: changes,
                action: { onSelectSection(.workingTree) }
            ),
            makeMetric(
                .branches,
                presentation: branches,
                action: { onSelectSection(.branches) }
            ),
            makeMetric(
                .stashes,
                presentation: stashes,
                action: { onSelectSection(.stashes) }
            ),
            makeGitHubMetric(
                .pullRequests,
                state: overview.openPullRequests,
                action: { onOpenGitHubPage(.pullRequests) }
            ),
            makeGitHubMetric(
                .issues,
                state: overview.openIssues,
                action: { onOpenGitHubPage(.issues) }
            )
        ]
    }

    private var changesPresentation: RepositoryOverviewMetricPresentation {
        guard !overview.isLoading else {
            return .init(value: "—", qualifier: "Checking…", accessibilityValue: "Checking…", state: .loading, isError: false)
        }
        guard !overview.isCleanWorkingTree else {
            return .init(value: "0", qualifier: "Clean", accessibilityValue: "0 changes, Clean", state: .known(0), isError: false)
        }
        let parts = [
            (overview.stagedCount, "staged"),
            (overview.unstagedCount, "modified"),
            (overview.untrackedCount, "untracked")
        ].filter { $0.0 > 0 }
        let detail = parts.map { "\($0.0) \($0.1)" }
        let qualifier = parts.count == 1 ? parts[0].1 : detail.joined(separator: ", ")
        let accessibilityDetail = detail.isEmpty ? "Clean" : detail.joined(separator: ", ")
        let count = overview.totalWorkingTreeCount
        return .init(
            value: "\(count)",
            qualifier: qualifier,
            accessibilityValue: "\(count) changes, \(accessibilityDetail)",
            state: .known(0),
            isError: false
        )
    }

    private var branchesPresentation: RepositoryOverviewMetricPresentation {
        let loading = overview.unmergedBranches.isLoading || overview.unpushedBranches.isLoading || overview.isLoading
        let error = !loading && overview.unmergedBranches == .unavailable && overview.unpushedBranches == .unavailable
        let unmerged = knownCount(in: overview.unmergedBranches)
        let unpushed = knownCount(in: overview.unpushedBranches)
        let value: String = if loading || error {
            "—"
        } else if let unmerged, unmerged > 0 {
            "\(unmerged)"
        } else if let unpushed {
            "\(unpushed)"
        } else {
            unmerged.map(String.init) ?? "—"
        }
        let qualifier: String
        let summary: String
        if loading {
            qualifier = "Checking…"
            summary = "Checking…"
        } else if error {
            qualifier = "Unavailable"
            summary = "Unavailable"
        } else if unmerged == nil, unpushed == nil {
            qualifier = "Unavailable"
            summary = "Unavailable"
        } else if let unmerged, unmerged > 0 {
            qualifier = unpushed.map { $0 > 0 ? "unmerged, \($0) unpushed" : "unmerged" } ?? "unmerged"
            summary = ["\(unmerged) unmerged \(unmerged == 1 ? "branch" : "branches")", unpushed.flatMap { $0 > 0 ? "\($0) unpushed \($0 == 1 ? "branch" : "branches")" : nil }].compactMap(\.self).joined(separator: ", ")
        } else if let unpushed, unpushed > 0 {
            qualifier = "unpushed"
            summary = unpushed == 1 ? "1 unpushed branch" : "\(unpushed) unpushed branches"
        } else {
            qualifier = unmerged == nil || unpushed == nil ? "Unavailable" : "All clear"
            summary = qualifier
        }
        return .init(
            value: value,
            qualifier: qualifier,
            accessibilityValue: appendLastChecked(to: summary),
            state: loading ? .loading : error ? .unavailable : .known(0),
            isError: error
        )
    }

    private var stashesPresentation: RepositoryOverviewMetricPresentation {
        let loading = overview.stashCount.isLoading || overview.isLoading
        let error = !loading && overview.stashCount == .unavailable
        let value: String
        let qualifier: String
        let accessibility: String
        switch overview.stashCount {
        case let .known(count) where !loading:
            value = count == 0 ? "None" : "\(count)"
            qualifier = count == 0 ? "" : "retained"
            accessibility = count == 0 ? "No stashes" : "\(count) \(count == 1 ? "stash" : "stashes") retained"
        case .unavailable where error:
            value = "—"
            qualifier = "Unavailable"
            accessibility = "Unavailable"
        default:
            value = "—"
            qualifier = loading ? "Checking…" : "Unavailable"
            accessibility = qualifier
        }
        return .init(
            value: value,
            qualifier: qualifier,
            accessibilityValue: loading ? accessibility : appendLastChecked(to: accessibility),
            state: loading ? .loading : error ? .unavailable : .known(0),
            isError: error
        )
    }

    private func knownCount(in state: RepositoryMetricState<Int>) -> Int? {
        if case let .known(count) = state {
            return count
        }
        return nil
    }

    private func makeMetric(
        _ definition: RepositoryOverviewMetricDefinition,
        presentation: RepositoryOverviewMetricPresentation,
        helpText: String? = nil,
        action: (() -> Void)?
    ) -> RepositoryOverviewMetric {
        RepositoryOverviewMetric(
            title: definition.title,
            shortTitle: definition.shortTitle,
            symbol: definition.symbol,
            value: presentation.value,
            qualifier: presentation.qualifier,
            state: presentation.state,
            isError: presentation.isError,
            accessibilityValue: presentation.accessibilityValue,
            helpText: helpText ?? presentation.accessibilityValue,
            accessibilityHint: definition.accessibilityHint,
            action: action
        )
    }

    private func makeGitHubMetric(
        _ definition: RepositoryOverviewMetricDefinition,
        state: RepositoryMetricState<Int>,
        action: @escaping () -> Void
    ) -> RepositoryOverviewMetric {
        let value: String
        let qualifier: String
        let accessibility: String
        let help: String
        switch state {
        case .loading:
            value = "—"
            qualifier = "Checking…"
            accessibility = appendLastChecked(to: "Checking…")
            help = "Checking…"
        case let .known(count):
            let noun = definition.title == "Issues" ? "issue" : "pull request"
            let countDescription = "\(count) open \(count == 1 ? noun : "\(noun)s")"
            value = "\(count)"
            qualifier = count == 0 ? "" : "open"
            accessibility = appendLastChecked(to: countDescription)
            help = countDescription
        case .unavailable:
            let copy = githubUnavailableCopy
            value = "—"
            qualifier = copy.qualifier
            accessibility = appendLastChecked(to: "Unavailable, \(copy.qualifier)")
            help = copy.help
        }
        return makeMetric(
            definition,
            presentation: .init(
                value: value,
                qualifier: qualifier,
                accessibilityValue: accessibility,
                state: state,
                isError: false
            ),
            helpText: help,
            action: canOpenGitHubPage && state != .unavailable ? action : nil
        )
    }

    private var githubUnavailableCopy: (qualifier: String, help: String) {
        switch overview.gitHubUnavailableReason {
        case .gitHubCLIMissing:
            ("Install GitHub CLI", "Install GitHub CLI")
        case .notGitHubRemote:
            ("Not on GitHub", "Not on GitHub")
        case .commandFailed:
            ("GitHub unavailable", "Run gh auth status to check sign-in")
        case nil:
            ("Unavailable", "Unavailable")
        }
    }

    private func appendLastChecked(to text: String) -> String {
        overview.lastCheckedAt.map {
            "\(text). Last checked \(DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short))"
        } ?? text
    }
}

private enum RepositoryOverviewMetricDensity: Equatable {
    case wide
    case medium
    case compact
}

private struct RepositoryOverviewMetricDefinition {
    let title: String
    let shortTitle: String
    let symbol: String
    let accessibilityHint: String

    init(_ title: String, _ shortTitle: String, _ symbol: String, _ accessibilityHint: String) {
        self.title = title
        self.shortTitle = shortTitle
        self.symbol = symbol
        self.accessibilityHint = accessibilityHint
    }

    static let changes = Self("Changes", "Changes", "plus.forwardslash.minus", "Opens Changes in the side panel")
    static let branches = Self("Branches", "Branches", "arrow.triangle.branch", "Opens Branches in the side panel")
    static let stashes = Self("Stashes", "Stashes", "tray.full", "Opens Stashes in the side panel")
    static let pullRequests = Self("Pull Requests", "PRs", "arrow.triangle.pull", "Opens pull requests on GitHub")
    static let issues = Self("Issues", "Issues", "smallcircle.filled.circle", "Opens issues on GitHub")
}

private struct RepositoryOverviewMetricPresentation {
    let value: String
    let qualifier: String
    let accessibilityValue: String
    let state: RepositoryMetricState<Int>
    let isError: Bool
}

private struct RepositoryOverviewMetric {
    let title: String
    let shortTitle: String
    let symbol: String
    let value: String
    let qualifier: String
    let state: RepositoryMetricState<Int>
    let isError: Bool
    let accessibilityValue: String
    let helpText: String
    let accessibilityHint: String
    let action: (() -> Void)?
}

private struct RepositoryOverviewMetricRowLayout: Layout {
    let density: RepositoryOverviewMetricDensity
    private var metricStride: Int {
        density == .compact ? 1 : 2
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        _ = cache
        let metricIndices = indices(in: subviews)
        let metricSizes = metricIndices.map { subviews[$0].sizeThatFits(ProposedViewSize(width: 0, height: nil)) }
        let dividerIndices = density == .compact ? [] : Array(stride(from: 1, to: subviews.count, by: metricStride))
        let dividerWidth = dividerIndices.reduce(CGFloat.zero) { width, index in
            width + subviews[index].sizeThatFits(.unspecified).width
        }
        let minimumWidth = (metricSizes.map(\.width).max() ?? 0) * CGFloat(metricSizes.count) + dividerWidth
        return CGSize(width: max(proposal.width ?? minimumWidth, minimumWidth), height: metricSizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        _ = (proposal, cache)
        let metricIndices = indices(in: subviews)
        guard !metricIndices.isEmpty else { return }
        let dividerIndices = density == .compact ? [] : Array(stride(from: 1, to: subviews.count, by: metricStride))
        let dividerWidths = dividerIndices.map { subviews[$0].sizeThatFits(.unspecified).width }
        let dividerWidth = dividerWidths.reduce(CGFloat.zero, +)
        let metricWidth = max((bounds.width - dividerWidth) / CGFloat(metricIndices.count), 0)
        var currentX = bounds.minX
        var dividerIndex = 0

        for index in metricIndices {
            subviews[index].place(
                at: CGPoint(x: currentX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: metricWidth, height: bounds.height)
            )
            currentX += metricWidth

            guard dividerIndex < dividerIndices.count else { continue }
            let divider = subviews[dividerIndices[dividerIndex]]
            let width = dividerWidths[dividerIndex]
            divider.place(
                at: CGPoint(x: currentX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            currentX += width
            dividerIndex += 1
        }
    }

    private func indices(in subviews: Subviews) -> [Int] {
        Array(stride(from: 0, to: subviews.count, by: metricStride))
    }
}

private struct RepositoryOverviewColumnView: View {
    let metric: RepositoryOverviewMetric
    let density: RepositoryOverviewMetricDensity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    var body: some View {
        Button(action: metric.action ?? {}) {
            metricContent
                .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                .padding(.vertical, density == .compact ? WorkbenchMetrics.microSpacing : WorkbenchMetrics.compactSpacing)
                .frame(
                    maxWidth: .infinity,
                    minHeight: WorkbenchMetrics.minimumHitTarget,
                    alignment: density == .compact ? .center : .leading
                )
                .background(
                    RoundedRectangle(
                        cornerRadius: density == .compact ? WorkbenchMetrics.microCornerRadius : WorkbenchMetrics.rowCornerRadius,
                        style: .continuous
                    )
                    .fill(isHovered ? WorkbenchPalette.hoverFill() : .clear)
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: density == .compact ? WorkbenchMetrics.microCornerRadius : WorkbenchMetrics.rowCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(metric.action == nil)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(metric.helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.accessibilityValue)
        .accessibilityHint(metric.accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var metricContent: some View {
        switch density {
        case .wide:
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                titleText(metric.title)
                valueRow
            }
        case .medium:
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                titleText(metric.shortTitle)
                valueText
            }
        case .compact:
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                Image(systemName: metric.symbol)
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                valueText
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(WorkbenchTypography.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.microSpacing) {
            valueText
            if !metric.qualifier.isEmpty {
                Text(metric.qualifier)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(qualifierForegroundStyle)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if metric.state == .loading {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        } else {
            Text(metric.value)
                .font(density == .compact ? WorkbenchTypography.captionStrong : WorkbenchTypography.field)
                .foregroundStyle(valueForegroundStyle)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(
                    WorkbenchMotion.adaptive(WorkbenchMotion.swap, usesReducedMotion: reduceMotion),
                    value: metric.value
                )
        }
    }

    private var valueForegroundStyle: Color {
        metric.isError ? .red : metric.value == "0" || metric.value == "—" ? .secondary : .primary
    }

    private var qualifierForegroundStyle: Color {
        metric.isError ? .red : .secondary
    }
}
