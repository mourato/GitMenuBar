import SwiftUI

struct RepositoryOverviewView: View {
    let overview: RepositoryOverviewSnapshot
    let onSelectSection: (MainMenuInspectorSelection) -> Void
    @State private var hoveredSelection: MainMenuInspectorSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            overviewCard(
                title: "Working Tree",
                selection: .workingTree,
                content: workingTreeContent,
                accessibilityValue: workingTreeContent
            )
            overviewCard(
                title: "Push and Sync",
                selection: .unpushedCommits,
                content: pushSyncContent,
                accessibilityValue: pushSyncAccessibilityValue
            )
            overviewCard(
                title: "Branch Health",
                selection: .branches,
                content: branchHealthContent,
                accessibilityValue: branchHealthAccessibilityValue
            )
            overviewCard(
                title: "Stashes",
                selection: .stashes,
                content: stashContent,
                accessibilityValue: stashAccessibilityValue
            )
            overviewCard(
                title: "History",
                selection: .history,
                content: historyContent,
                accessibilityValue: historyContent
            )
        }
        .adaptiveMotion()
    }

    private func overviewCard(
        title: String,
        selection: MainMenuInspectorSelection,
        content: String,
        accessibilityValue: String
    ) -> some View {
        let isLoading = content.hasPrefix("Checking")
        return Button {
            onSelectSection(selection)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.compactSpacing) {
                VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                    Text(title)
                        .font(WorkbenchTypography.sectionLabel)
                    Text(content)
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(WorkbenchMetrics.sectionSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .workbenchPanelSurface(
            cornerRadius: WorkbenchMetrics.cornerRadius,
            material: .thin
        )
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                .fill(hoveredSelection == selection ? WorkbenchPalette.hoverFill() : Color.clear)
                .accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                .stroke(WorkbenchPalette.neutralBorder(contrast: .standard), lineWidth: 1)
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
