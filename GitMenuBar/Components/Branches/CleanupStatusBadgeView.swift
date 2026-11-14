import SwiftUI

struct CleanupStatusBadgeView: View {
    private enum Tone {
        case success
        case warning
        case neutral
        case error
    }

    private let title: String
    private let icon: LucideIconName
    private let tone: Tone

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(status: GitBranchCleanupStatus) {
        switch status {
        case .mergedIntoDefault:
            title = "Merged"
            icon = .circleCheck
            tone = .success
        case .notMerged:
            title = "Not merged"
            icon = .gitBranch
            tone = .warning
        case .protected:
            title = "Protected"
            icon = .lock
            tone = .neutral
        case .current:
            title = "Current"
            icon = .check
            tone = .neutral
        case .checkedOutElsewhere:
            title = "In worktree"
            icon = .layers
            tone = .neutral
        case .unknown:
            title = "Unknown"
            icon = .circleHelp
            tone = .error
        }
    }

    init(status: GitWorktreeCleanupStatus) {
        switch status {
        case .eligible:
            title = "Eligible"
            icon = .circleCheck
            tone = .success
        case .main:
            title = "Main worktree"
            icon = .house
            tone = .neutral
        case .current:
            title = "Current"
            icon = .mapPin
            tone = .neutral
        case .dirty:
            title = "Dirty"
            icon = .triangleAlert
            tone = .warning
        case .locked:
            title = "Locked"
            icon = .lock
            tone = .warning
        case .prunable:
            title = "Prunable"
            icon = .trash2
            tone = .warning
        case .branchNotMerged:
            title = "Not merged"
            icon = .gitBranch
            tone = .warning
        case .detached:
            title = "Detached"
            icon = .boxSelect
            tone = .neutral
        case .unknown:
            title = "Unknown"
            icon = .circleHelp
            tone = .error
        }
    }

    var body: some View {
        Label(lucide: icon, title)
            .font(WorkbenchTypography.captionStrong)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        switch tone {
        case .success:
            .green
        case .warning:
            .orange
        case .neutral:
            .secondary
        case .error:
            .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .success:
            WorkbenchPalette.successFill(contrast: colorSchemeContrast)
        case .warning:
            WorkbenchPalette.warningFill(contrast: colorSchemeContrast)
        case .neutral:
            WorkbenchPalette.hoverFill()
        case .error:
            WorkbenchPalette.errorFill(contrast: colorSchemeContrast)
        }
    }
}

#Preview("Cleanup Status Badges") {
    VStack(alignment: .leading, spacing: 8) {
        CleanupStatusBadgeView(status: .mergedIntoDefault)
        CleanupStatusBadgeView(status: .dirty)
        CleanupStatusBadgeView(status: GitBranchCleanupStatus.unknown(reason: "Unavailable"))
    }
    .padding()
}
