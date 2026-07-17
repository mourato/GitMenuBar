import SwiftUI

struct CleanupStatusBadgeView: View {
    private enum Tone {
        case success
        case warning
        case neutral
        case error
    }

    private let title: String
    private let systemImage: String
    private let tone: Tone

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(status: GitBranchCleanupStatus) {
        switch status {
        case .mergedIntoDefault:
            title = "Merged"
            systemImage = "checkmark.circle.fill"
            tone = .success
        case .notMerged:
            title = "Not merged"
            systemImage = "arrow.triangle.branch"
            tone = .warning
        case .protected:
            title = "Protected"
            systemImage = "lock.fill"
            tone = .neutral
        case .current:
            title = "Current"
            systemImage = "checkmark"
            tone = .neutral
        case .checkedOutElsewhere:
            title = "In worktree"
            systemImage = "square.stack.3d.up"
            tone = .neutral
        case .unknown:
            title = "Unknown"
            systemImage = "questionmark.circle"
            tone = .error
        }
    }

    init(status: GitWorktreeCleanupStatus) {
        switch status {
        case .eligible:
            title = "Eligible"
            systemImage = "checkmark.circle.fill"
            tone = .success
        case .main:
            title = "Main worktree"
            systemImage = "house.fill"
            tone = .neutral
        case .current:
            title = "Current"
            systemImage = "location.fill"
            tone = .neutral
        case .dirty:
            title = "Dirty"
            systemImage = "exclamationmark.triangle.fill"
            tone = .warning
        case .locked:
            title = "Locked"
            systemImage = "lock.fill"
            tone = .warning
        case .prunable:
            title = "Prunable"
            systemImage = "trash"
            tone = .warning
        case .branchNotMerged:
            title = "Not merged"
            systemImage = "arrow.triangle.branch"
            tone = .warning
        case .detached:
            title = "Detached"
            systemImage = "rectangle.dashed"
            tone = .neutral
        case .unknown:
            title = "Unknown"
            systemImage = "questionmark.circle"
            tone = .error
        }
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(MacChromeTypography.captionStrong)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        switch tone {
        case .success:
            return .green
        case .warning:
            return .orange
        case .neutral:
            return .secondary
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .success:
            return MacChromePalette.successFill(contrast: colorSchemeContrast)
        case .warning:
            return MacChromePalette.warningFill(contrast: colorSchemeContrast)
        case .neutral:
            return MacChromePalette.hoverFill()
        case .error:
            return MacChromePalette.errorFill(contrast: colorSchemeContrast)
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
