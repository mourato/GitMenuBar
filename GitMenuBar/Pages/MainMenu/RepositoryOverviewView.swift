import SwiftUI

private struct RepositoryOverviewCardVisual {
    let systemImage: String
    let color: Color
    let metric: String
}

struct RepositoryOverviewView: View {
    let overview: RepositoryOverviewSnapshot
    let onSelectSection: (MainMenuInspectorSelection) -> Void
    @State private var hoveredSelection: MainMenuInspectorSelection?

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: WorkbenchMetrics.sectionSpacing),
                GridItem(.flexible(), spacing: WorkbenchMetrics.sectionSpacing)
            ],
            spacing: WorkbenchMetrics.sectionSpacing
        ) {
            overviewCard(
                title: "Working Tree",
                visual: RepositoryOverviewCardVisual(
                    systemImage: overview.isCleanWorkingTree ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    color: overview.isCleanWorkingTree ? .green : .orange,
                    metric: "\(overview.totalWorkingTreeCount)"
                ),
                selection: .workingTree,
                content: workingTreeContent,
                accessibilityValue: workingTreeContent
            )
            overviewCard(
                title: "Push and Sync",
                visual: RepositoryOverviewCardVisual(systemImage: "arrow.up.arrow.down.circle.fill", color: .blue, metric: pushSyncMetric),
                selection: .unpushedCommits,
                content: pushSyncContent,
                accessibilityValue: pushSyncAccessibilityValue
            )
            overviewCard(
                title: "Branch Health",
                visual: RepositoryOverviewCardVisual(systemImage: "arrow.triangle.branch", color: .purple, metric: branchHealthMetric),
                selection: .branches,
                content: branchHealthContent,
                accessibilityValue: branchHealthAccessibilityValue
            )
            overviewCard(
                title: "Stashes",
                visual: RepositoryOverviewCardVisual(systemImage: "archivebox.fill", color: .orange, metric: stashMetric),
                selection: .stashes,
                content: stashContent,
                accessibilityValue: stashAccessibilityValue
            )
            overviewCard(
                title: "History",
                visual: RepositoryOverviewCardVisual(systemImage: "clock.fill", color: .indigo, metric: "\(overview.historyCount)"),
                selection: .history,
                content: historyContent,
                accessibilityValue: historyContent
            )
        }
        .adaptiveMotion()
    }

    private func overviewCard(
        title: String,
        visual: RepositoryOverviewCardVisual,
        selection: MainMenuInspectorSelection,
        content: String,
        accessibilityValue: String
    ) -> some View {
        let isLoading = content.hasPrefix("Checking")
        let shape = RoundedRectangle(cornerRadius: WorkbenchMetrics.largeCornerRadius, style: .continuous)
        return Button {
            onSelectSection(selection)
        } label: {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                HStack(alignment: .top, spacing: WorkbenchMetrics.compactSpacing) {
                    Image(systemName: visual.systemImage)
                        .font(.title3.weight(.medium))
                        .accessibilityHidden(true)

                    Spacer(minLength: 0)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .accessibilityHidden(true)
                    } else {
                        Text(visual.metric)
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                Spacer(minLength: WorkbenchMetrics.microSpacing)

                Text(title)
                    .font(WorkbenchTypography.windowTitle)
                    .lineLimit(1)

                Text(content)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.white.opacity(0.86))
                    .monospacedDigit()
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(WorkbenchMetrics.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background(
            LinearGradient(
                colors: [visual.color, visual.color.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: shape
        )
        .overlay {
            shape
                .fill(hoveredSelection == selection ? Color.white.opacity(0.10) : Color.clear)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .overlay {
            shape
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { inside in
            hoveredSelection = inside ? selection : nil
        }
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
        composedMetricSummary(
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
        composedMetricAccessibility(
            (overview.aheadCount, "commits ahead"),
            (overview.behindCount, "commits behind"),
            emptyKnown: "Up to date"
        )
    }

    private var branchHealthContent: String {
        composedMetricSummary(
            (overview.unmergedBranches, "unmerged"),
            (overview.unpushedBranches, "unpushed"),
            (overview.branchesWithoutUpstream, "no upstream"),
            emptyKnown: "All clear"
        )
    }

    private var branchHealthMetric: String {
        guard
            case let .known(unmerged) = overview.unmergedBranches,
            case let .known(unpushed) = overview.unpushedBranches,
            case let .known(withoutUpstream) = overview.branchesWithoutUpstream
        else {
            return "—"
        }
        return "\(unmerged + unpushed + withoutUpstream)"
    }

    private var branchHealthAccessibilityValue: String {
        let summary = composedMetricAccessibility(
            (overview.unmergedBranches, "unmerged branches"),
            (overview.unpushedBranches, "unpushed branches"),
            (overview.branchesWithoutUpstream, "branches without upstream"),
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

    private var historyContent: String {
        let branchPart = if overview.isDetachedHead {
            "Detached HEAD"
        } else if let branch = overview.currentBranch {
            branch
        } else {
            "No branch"
        }

        if overview.historyCount > 0 {
            return "\(overview.historyCount) loaded on \(branchPart)"
        }
        return branchPart
    }

    private func composedMetricSummary(
        _ metrics: (RepositoryMetricState<Int>, String)...,
        emptyKnown: String
    ) -> String {
        composeMetricParts(metrics, emptyKnown: emptyKnown)
    }

    private func composedMetricAccessibility(
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
