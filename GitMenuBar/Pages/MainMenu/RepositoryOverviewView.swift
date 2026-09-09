import SwiftUI

private struct RepositoryOverviewCardVisual {
    let systemImage: String
    let tint: Color
    let metric: String
}

struct RepositoryOverviewView: View {
    let overview: RepositoryOverviewSnapshot
    let onSelectSection: (MainMenuSidePanelSelection) -> Void
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(spacing: 0) {
            overviewRow(
                title: "Working Tree",
                visual: RepositoryOverviewCardVisual(
                    systemImage: overview.isCleanWorkingTree ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    tint: overview.isCleanWorkingTree ? .green : .orange,
                    metric: "\(overview.totalWorkingTreeCount)"
                ),
                selection: .workingTree,
                isLoading: false,
                content: workingTreeContent,
                accessibilityValue: workingTreeContent
            )
            Divider()
                .padding(.leading, WorkbenchMetrics.panelPadding)

            overviewRow(
                title: "Push and Sync",
                visual: RepositoryOverviewCardVisual(systemImage: "arrow.up.arrow.down.circle.fill", tint: .accentColor, metric: pushSyncMetric),
                selection: .unpushedCommits,
                isLoading: overview.aheadCount.isLoading || overview.behindCount.isLoading,
                content: pushSyncContent,
                accessibilityValue: pushSyncAccessibilityValue
            )
            Divider()
                .padding(.leading, WorkbenchMetrics.panelPadding)

            overviewRow(
                title: "Branch Health",
                visual: RepositoryOverviewCardVisual(systemImage: "arrow.triangle.branch", tint: .secondary, metric: branchHealthMetric),
                selection: .branches,
                isLoading: overview.unmergedBranches.isLoading || overview.unpushedBranches.isLoading,
                content: branchHealthContent,
                accessibilityValue: branchHealthAccessibilityValue
            )
            Divider()
                .padding(.leading, WorkbenchMetrics.panelPadding)

            overviewRow(
                title: "Stashes",
                visual: RepositoryOverviewCardVisual(systemImage: "archivebox.fill", tint: .secondary, metric: stashMetric),
                selection: .stashes,
                isLoading: overview.stashCount.isLoading,
                content: stashContent,
                accessibilityValue: stashAccessibilityValue
            )
        }
        .padding(.vertical, WorkbenchMetrics.microSpacing)
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

    // swiftlint:disable:next function_parameter_count
    private func overviewRow(
        title: String,
        visual: RepositoryOverviewCardVisual,
        selection: MainMenuSidePanelSelection,
        isLoading: Bool,
        content: String,
        accessibilityValue: String
    ) -> some View {
        Button {
            onSelectSection(selection)
        } label: {
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Image(systemName: visual.systemImage)
                    .font(WorkbenchTypography.detail.weight(.semibold))
                    .foregroundStyle(visual.tint)
                    .frame(width: WorkbenchMetrics.iconHitTarget, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    Text(title)
                        .font(WorkbenchTypography.windowTitle)
                        .lineLimit(1)

                    Text(content)
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                }

                Spacer(minLength: WorkbenchMetrics.compactSpacing)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.accentColor)
                        .accessibilityHidden(true)
                } else {
                    Text(visual.metric)
                        .font(WorkbenchTypography.field)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Image(systemName: "chevron.right")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(WorkbenchMetrics.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(accessibilityValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens \(title) in the inspector")
        .accessibilityAddTraits(.isButton)
    }

    private var workingTreeContent: String {
        if overview.isCleanWorkingTree {
            return "Clean"
        }
        var parts: [String] = []
        if overview.stagedCount > 0 {
            parts.append("\(overview.stagedCount) staged")
        }
        if overview.unstagedCount > 0 {
            parts.append("\(overview.unstagedCount) modified")
        }
        if overview.untrackedCount > 0 {
            parts.append("\(overview.untrackedCount) untracked")
        }
        if overview.addedLineCount > 0 || overview.removedLineCount > 0 {
            parts.append("+\(overview.addedLineCount) −\(overview.removedLineCount)")
        }
        return parts.joined(separator: ", ")
    }

    private var pushSyncContent: String {
        composedMetricText(
            (overview.aheadCount, "ahead"),
            (overview.behindCount, "behind"),
            emptyKnown: "Up to date"
        )
    }

    private var pushSyncMetric: String {
        guard
            case let .known(ahead) = overview.aheadCount,
            case let .known(behind) = overview.behindCount
        else {
            return "—"
        }
        return "↑\(ahead) ↓\(behind)"
    }

    private var pushSyncAccessibilityValue: String {
        composedMetricText(
            (overview.aheadCount, "commits ahead"),
            (overview.behindCount, "commits behind"),
            emptyKnown: "Up to date"
        )
    }

    private var branchHealthContent: String {
        composedMetricText(
            (overview.unmergedBranches, "unmerged"),
            (overview.unpushedBranches, "unpushed"),
            emptyKnown: "All clear"
        )
    }

    private var branchHealthMetric: String {
        guard
            case let .known(unmerged) = overview.unmergedBranches,
            case let .known(unpushed) = overview.unpushedBranches
        else {
            return "—"
        }
        return "\(unmerged + unpushed)"
    }

    private var branchHealthAccessibilityValue: String {
        let summary = composedMetricText(
            (overview.unmergedBranches, "unmerged branches"),
            (overview.unpushedBranches, "unpushed branches"),
            emptyKnown: "All clear"
        )
        return appendLastChecked(to: summary)
    }

    private var stashContent: String {
        switch overview.stashCount {
        case let .known(count):
            count == 0 ? "None" : "\(count) retained"
        case .loading:
            "Checking…"
        case .unavailable:
            "Not available"
        }
    }

    private var stashMetric: String {
        switch overview.stashCount {
        case let .known(count):
            "\(count)"
        case .loading, .unavailable:
            "—"
        }
    }

    private var stashAccessibilityValue: String {
        appendLastChecked(to: stashContent)
    }

    private func composedMetricText(
        _ metrics: (RepositoryMetricState<Int>, String)...,
        emptyKnown: String
    ) -> String {
        composeMetricParts(metrics, emptyKnown: emptyKnown)
    }

    private func composeMetricParts(
        _ metrics: [(RepositoryMetricState<Int>, String)],
        emptyKnown: String
    ) -> String {
        var parts: [String] = []
        var sawLoading = false
        var sawUnavailable = false
        var sawKnown = false

        for (metric, label) in metrics {
            switch metric {
            case let .known(count):
                sawKnown = true
                if count > 0 {
                    parts.append("\(count) \(label)")
                }
            case .loading:
                sawLoading = true
            case .unavailable:
                sawUnavailable = true
            }
        }

        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }
        if sawLoading {
            return "Checking…"
        }
        if sawUnavailable, !sawKnown {
            return "Not available"
        }
        if sawUnavailable {
            return "Unavailable"
        }
        return emptyKnown
    }

    private func appendLastChecked(to value: String) -> String {
        guard let lastCheckedAt = overview.lastCheckedAt else {
            return value
        }
        let formatted = lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(value). Last checked \(formatted)"
    }
}

#Preview("Dirty repository") {
    RepositoryOverviewView(
        overview: RepositoryOverviewSnapshot(
            stagedCount: 3,
            unstagedCount: 5,
            untrackedCount: 2,
            addedLineCount: 40,
            removedLineCount: 12,
            aheadCount: .known(4),
            behindCount: .known(1),
            branchesWithoutUpstream: .known(1),
            unpushedBranches: .known(2),
            unmergedBranches: .known(0),
            stashCount: .known(3),
            historyCount: 42,
            currentBranch: "feature/overview",
            isDetachedHead: false,
            isLoading: false,
            lastCheckedAt: Date()
        ),
        onSelectSection: { _ in }
    )
    .frame(width: 380)
    .padding()
}

#Preview("Clean repository") {
    RepositoryOverviewView(
        overview: RepositoryOverviewSnapshot(
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            addedLineCount: 0,
            removedLineCount: 0,
            aheadCount: .known(0),
            behindCount: .known(0),
            branchesWithoutUpstream: .known(0),
            unpushedBranches: .known(0),
            unmergedBranches: .known(0),
            stashCount: .known(0),
            historyCount: 100,
            currentBranch: "main",
            isDetachedHead: false,
            isLoading: false,
            lastCheckedAt: Date()
        ),
        onSelectSection: { _ in }
    )
    .frame(width: 380)
    .padding()
}

#Preview("Loading state") {
    RepositoryOverviewView(
        overview: RepositoryOverviewSnapshot(
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            addedLineCount: 0,
            removedLineCount: 0,
            aheadCount: .known(0),
            behindCount: .known(0),
            branchesWithoutUpstream: .loading,
            unpushedBranches: .loading,
            unmergedBranches: .loading,
            stashCount: .loading,
            historyCount: 0,
            currentBranch: "main",
            isDetachedHead: false,
            isLoading: true,
            lastCheckedAt: nil
        ),
        onSelectSection: { _ in }
    )
    .frame(width: 380)
    .padding()
}

#Preview("Unavailable state") {
    RepositoryOverviewView(
        overview: RepositoryOverviewSnapshot(
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            addedLineCount: 0,
            removedLineCount: 0,
            aheadCount: .known(0),
            behindCount: .known(0),
            branchesWithoutUpstream: .unavailable,
            unpushedBranches: .unavailable,
            unmergedBranches: .unavailable,
            stashCount: .unavailable,
            historyCount: 25,
            currentBranch: nil,
            isDetachedHead: true,
            isLoading: false,
            lastCheckedAt: nil
        ),
        onSelectSection: { _ in }
    )
    .frame(width: 380)
    .padding()
}
