import SwiftUI

struct RepositoryOverviewView: View {
    let overview: RepositoryOverviewSnapshot
    let selection: MainMenuSidePanelSelection?
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
                    density: density,
                    isSelected: metric.panel != nil && metric.panel == activePanel
                )

                if index < metrics.count - 1, density != .compact {
                    metricDivider(from: metric, to: metrics[index + 1])
                }
            }
        }
    }

    @ViewBuilder
    private func metricDivider(
        from current: RepositoryOverviewMetric,
        to next: RepositoryOverviewMetric
    ) -> some View {
        if current.group == next.group {
            HStack(spacing: 0) {
                Divider()
                    .padding(.vertical, WorkbenchMetrics.microSpacing)
            }
        } else {
            HStack(spacing: 0) {
                Divider()
            }
            .padding(.horizontal, WorkbenchMetrics.microSpacing)
        }
    }

    private var activePanel: RepositoryOverviewMetricPanel? {
        switch selection {
        case .workingTree, .stagedFile, .unstagedFile: .changes
        case .branches, .branch, .unpushedCommits: .branches
        case .stashes, .stash: .stashes
        case .history, .commit, nil: nil
        }
    }

    private var metrics: [RepositoryOverviewMetric] {
        let changes = changesPresentation
        let branches = branchesPresentation
        let stashes = stashesPresentation
        return [
            makeMetric(
                .changes,
                panel: .changes,
                presentation: changes,
                action: { onSelectSection(.workingTree) }
            ),
            makeMetric(
                .branches,
                panel: .branches,
                presentation: branches,
                action: { onSelectSection(.branches) }
            ),
            makeMetric(
                .stashes,
                panel: .stashes,
                presentation: stashes,
                action: { onSelectSection(.stashes) }
            ),
            makeGitHubMetric(
                .issues,
                panel: nil,
                state: overview.openIssues,
                requiresKnownCount: false,
                action: { onOpenGitHubPage(.issues) }
            ),
            makeGitHubMetric(
                .pullRequests,
                state: overview.openPullRequests,
                action: { onOpenGitHubPage(.pullRequests) }
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
        panel: RepositoryOverviewMetricPanel? = nil,
        presentation: RepositoryOverviewMetricPresentation,
        helpText: String? = nil,
        action: (() -> Void)?
    ) -> RepositoryOverviewMetric {
        RepositoryOverviewMetric(
            title: definition.title,
            shortTitle: definition.shortTitle,
            symbol: definition.symbol,
            group: definition.group,
            marker: definition.marker,
            value: presentation.value,
            qualifier: presentation.qualifier,
            state: presentation.state,
            emphasis: emphasis(for: presentation.value),
            isError: presentation.isError,
            panel: panel,
            accessibilityValue: presentation.accessibilityValue,
            helpText: helpText ?? presentation.accessibilityValue,
            accessibilityHint: definition.accessibilityHint,
            action: action
        )
    }

    private func emphasis(for value: String) -> RepositoryOverviewMetricEmphasis {
        guard let count = Int(value), count > 0 else {
            return .quiet
        }
        return .strong
    }

    private func makeGitHubMetric(
        _ definition: RepositoryOverviewMetricDefinition,
        panel: RepositoryOverviewMetricPanel? = nil,
        state: RepositoryMetricState<Int>,
        requiresKnownCount: Bool = true,
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
            panel: panel,
            presentation: .init(
                value: value,
                qualifier: qualifier,
                accessibilityValue: accessibility,
                state: state,
                isError: false
            ),
            helpText: help,
            action: canOpenGitHubPage && (!requiresKnownCount || state != .unavailable) ? action : nil
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

private struct RepositoryOverviewColumnView: View {
    let metric: RepositoryOverviewMetric
    let density: RepositoryOverviewMetricDensity
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isActionable: Bool {
        metric.action != nil
    }

    private var cellShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: density == .compact ? WorkbenchMetrics.microCornerRadius : WorkbenchMetrics.rowCornerRadius,
            style: .continuous
        )
    }

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
                .background(cellShape.fill(cellFill))
                .contentShape(cellShape)
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .onHover { hovering in
            isHovered = hovering && isActionable
        }
        .overlay(alignment: .topTrailing) { openingHint }
        .help(metric.helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.accessibilityValue)
        .accessibilityHint(isActionable ? metric.accessibilityHint : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var openingHint: some View {
        if density != .compact, isActionable, isHovered || isSelected {
            LucideIconView(name: .chevronRight, size: 10)
                .foregroundStyle(.tertiary)
                .padding(.top, WorkbenchMetrics.compactSpacing)
                .padding(.trailing, WorkbenchMetrics.compactSpacing)
                .allowsHitTesting(false)
        }
    }

    private var cellFill: Color {
        if isSelected {
            return WorkbenchPalette.neutralSelectionFill()
        }
        return isHovered && isActionable ? WorkbenchPalette.hoverFill() : .clear
    }

    @ViewBuilder
    private var metricContent: some View {
        switch density {
        case .wide:
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                titleRow(metric.title)
                valueRow
            }
        case .medium:
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                titleRow(metric.shortTitle)
                valueText
            }
        case .compact:
            HStack(spacing: WorkbenchMetrics.chipSpacing) {
                LucideIconView(name: metric.symbol, size: 12)
                    .foregroundStyle(compactIconForegroundStyle)
                valueText
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func titleRow(_ title: String) -> some View {
        HStack(spacing: WorkbenchMetrics.microSpacing) {
            if let marker = metric.marker {
                LucideIconView(name: metric.symbol, size: 11)
                    .foregroundStyle(marker.color)
            }
            Text(title)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.microSpacing) {
            valueText
            ViewThatFits(in: .horizontal) {
                Text(metric.qualifier).font(WorkbenchTypography.caption).foregroundStyle(qualifierForegroundStyle)
                    .lineLimit(1).fixedSize()
                Color.clear.frame(width: 0, height: 0)
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
                .font(valueFont)
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

    private var compactIconForegroundStyle: Color {
        metric.marker?.color ?? .secondary
    }

    private var valueFont: Font {
        switch (density, metric.emphasis) {
        case (.compact, .quiet): WorkbenchTypography.caption
        case (.compact, .strong): WorkbenchTypography.captionStrong
        case (_, .quiet): WorkbenchTypography.detail
        case (_, .strong): WorkbenchTypography.field
        }
    }

    private var valueForegroundStyle: Color {
        metric.isError ? .red : metric.emphasis == .quiet ? .secondary : .primary
    }

    private var qualifierForegroundStyle: Color {
        metric.isError ? .red : .secondary
    }
}
