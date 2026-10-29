import SwiftUI

struct RepositoryOverviewView: View {
    let overview: RepositoryOverviewSnapshot
    let onSelectSection: (MainMenuSidePanelSelection) -> Void
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 0) {
            changesColumn

            Divider()
                .padding(.vertical, WorkbenchMetrics.microSpacing)

            branchesColumn

            Divider()
                .padding(.vertical, WorkbenchMetrics.microSpacing)

            stashesColumn
        }
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

    // MARK: - Columns

    private var changesColumn: some View {
        RepositoryOverviewColumnView(
            title: "Changes",
            value: changesValue,
            qualifier: changesQualifier,
            isLoading: changesIsLoading,
            isError: false,
            accessibilityValue: changesAccessibilityValue,
            action: { onSelectSection(.workingTree) }
        )
    }

    private var branchesColumn: some View {
        RepositoryOverviewColumnView(
            title: "Branches",
            value: branchesValue,
            qualifier: branchesQualifier,
            isLoading: branchesIsLoading,
            isError: branchesIsError,
            accessibilityValue: branchesAccessibilityValue,
            action: { onSelectSection(.branches) }
        )
    }

    private var stashesColumn: some View {
        RepositoryOverviewColumnView(
            title: "Stashes",
            value: stashesValue,
            qualifier: stashesQualifier,
            isLoading: stashesIsLoading,
            isError: stashesIsError,
            accessibilityValue: stashesAccessibilityValue,
            action: { onSelectSection(.stashes) }
        )
    }

    // MARK: - Changes Computation

    private var changesIsLoading: Bool {
        overview.isLoading
    }

    private var changesValue: String {
        if changesIsLoading {
            return "—"
        }
        return "\(overview.totalWorkingTreeCount)"
    }

    private var changesQualifier: String {
        if changesIsLoading {
            return "Checking…"
        }
        if overview.isCleanWorkingTree {
            return "Clean"
        }
        // The value column already shows the total; repeat a count only when kinds are mixed.
        let parts = [
            (overview.stagedCount, "staged"),
            (overview.unstagedCount, "modified"),
            (overview.untrackedCount, "untracked")
        ].filter { $0.0 > 0 }
        if parts.count == 1 {
            return parts[0].1
        }
        return parts.map { "\($0.0) \($0.1)" }.joined(separator: ", ")
    }

    private var changesAccessibilityValue: String {
        if changesIsLoading {
            return "Checking…"
        }
        if overview.isCleanWorkingTree {
            return "0 changes, Clean"
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
        let detail = parts.isEmpty ? "Clean" : parts.joined(separator: ", ")
        return "\(overview.totalWorkingTreeCount) changes, \(detail)"
    }

    // MARK: - Branches Computation

    private var branchesIsLoading: Bool {
        overview.unmergedBranches.isLoading || overview.unpushedBranches.isLoading || overview.isLoading
    }

    private var branchesIsError: Bool {
        if branchesIsLoading {
            return false
        }
        switch (overview.unmergedBranches, overview.unpushedBranches) {
        case (.unavailable, .unavailable):
            return true
        default:
            return false
        }
    }

    /// Unmerged and unpushed branches can overlap, so the value never sums them:
    /// it leads with unmerged and the qualifier names any unpushed count separately.
    private var branchesValue: String {
        if branchesIsLoading || branchesIsError {
            return "—"
        }
        if let unmerged = knownUnmerged, unmerged > 0 {
            return "\(unmerged)"
        }
        if let unpushed = knownUnpushed {
            return "\(unpushed)"
        }
        return knownUnmerged.map { "\($0)" } ?? "—"
    }

    private var branchesQualifier: String {
        if branchesIsLoading {
            return "Checking…"
        }
        if branchesIsError {
            return "Unavailable"
        }
        let unmerged = knownUnmerged
        let unpushed = knownUnpushed
        if unmerged == nil, unpushed == nil {
            return "Unavailable"
        }
        if let unmerged, unmerged > 0 {
            if let unpushed, unpushed > 0 {
                return "unmerged, \(unpushed) unpushed"
            }
            return "unmerged"
        }
        if let unpushed, unpushed > 0 {
            return "unpushed"
        }
        // "All clear" needs both metrics known; a known zero beside an unavailable one is not clear.
        return unmerged == nil || unpushed == nil ? "Unavailable" : "All clear"
    }

    private var branchesAccessibilityValue: String {
        let summary: String
        if branchesIsLoading {
            summary = "Checking…"
        } else if branchesIsError {
            summary = "Unavailable"
        } else if knownUnmerged != nil || knownUnpushed != nil {
            var parts: [String] = []
            if let unmerged = knownUnmerged, unmerged > 0 {
                parts.append("\(unmerged) unmerged \(unmerged == 1 ? "branch" : "branches")")
            }
            if let unpushed = knownUnpushed, unpushed > 0 {
                parts.append("\(unpushed) unpushed \(unpushed == 1 ? "branch" : "branches")")
            }
            if !parts.isEmpty {
                summary = parts.joined(separator: ", ")
            } else {
                summary = knownUnmerged == nil || knownUnpushed == nil ? "Unavailable" : "All clear"
            }
        } else {
            summary = "Unavailable"
        }
        return appendLastChecked(to: summary)
    }

    private var knownUnmerged: Int? {
        if case let .known(count) = overview.unmergedBranches {
            return count
        }
        return nil
    }

    private var knownUnpushed: Int? {
        if case let .known(count) = overview.unpushedBranches {
            return count
        }
        return nil
    }

    // MARK: - Stashes Computation

    private var stashesIsLoading: Bool {
        overview.stashCount.isLoading || overview.isLoading
    }

    private var stashesIsError: Bool {
        if stashesIsLoading {
            return false
        }
        if case .unavailable = overview.stashCount {
            return true
        }
        return false
    }

    private var stashesValue: String {
        if stashesIsLoading || stashesIsError {
            return "—"
        }
        switch overview.stashCount {
        case let .known(count):
            return count == 0 ? "None" : "\(count)"
        case .loading, .unavailable:
            return "—"
        }
    }

    private var stashesQualifier: String {
        if stashesIsLoading {
            return "Checking…"
        }
        if stashesIsError {
            return "Unavailable"
        }
        switch overview.stashCount {
        case let .known(count):
            return count == 0 ? "" : "retained"
        case .loading:
            return "Checking…"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var stashesAccessibilityValue: String {
        if stashesIsLoading {
            return "Checking…"
        }
        let summary: String = switch overview.stashCount {
        case let .known(count):
            count == 0 ? "No stashes" : "\(count) \(count == 1 ? "stash" : "stashes") retained"
        case .loading:
            "Checking…"
        case .unavailable:
            "Unavailable"
        }
        return appendLastChecked(to: summary)
    }

    // MARK: - Helpers

    private func appendLastChecked(to text: String) -> String {
        guard let lastCheckedAt = overview.lastCheckedAt else {
            return text
        }
        return "\(text). Last checked \(Self.timeFormatter.string(from: lastCheckedAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

// MARK: - Column View

private struct RepositoryOverviewColumnView: View {
    let title: String
    let value: String
    let qualifier: String
    let isLoading: Bool
    let isError: Bool
    let accessibilityValue: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
                Text(title)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.microSpacing) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    } else {
                        Text(value)
                            .font(WorkbenchTypography.field)
                            .foregroundStyle(valueForegroundStyle)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                    }

                    if !qualifier.isEmpty {
                        Text(qualifier)
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(qualifierForegroundStyle)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, WorkbenchMetrics.compactSpacing)
            .padding(.vertical, WorkbenchMetrics.compactSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous)
                    .fill(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(accessibilityValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens \(title) in the side panel")
        .accessibilityAddTraits(.isButton)
    }

    private var valueForegroundStyle: Color {
        if isError {
            return .red
        }
        if value == "0" || value == "—" {
            return .secondary
        }
        return .primary
    }

    private var qualifierForegroundStyle: Color {
        if isError {
            return .red
        }
        return .secondary
    }
}

#Preview("Dirty repository") {
    RepositoryOverviewView(
        overview: RepositoryOverviewSnapshot(
            stagedCount: 3,
            unstagedCount: 5,
            untrackedCount: 1,
            addedLineCount: 40,
            removedLineCount: 12,
            aheadCount: .known(1),
            behindCount: .known(0),
            branchesWithoutUpstream: .known(0),
            unpushedBranches: .known(2),
            unmergedBranches: .known(1),
            stashCount: .known(3),
            historyCount: 24,
            currentBranch: "feat/status-strip",
            isDetachedHead: false,
            isLoading: false,
            lastCheckedAt: Date()
        ),
        onSelectSection: { _ in }
    )
    .frame(width: 380)
    .padding()
}

#Preview("Clean repository (Empty state)") {
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
            historyCount: 12,
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
            aheadCount: .loading,
            behindCount: .loading,
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

#Preview("Error state (Unavailable)") {
    RepositoryOverviewView(
        overview: RepositoryOverviewSnapshot(
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            addedLineCount: 0,
            removedLineCount: 0,
            aheadCount: .unavailable,
            behindCount: .unavailable,
            branchesWithoutUpstream: .unavailable,
            unpushedBranches: .unavailable,
            unmergedBranches: .unavailable,
            stashCount: .unavailable,
            historyCount: 0,
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
