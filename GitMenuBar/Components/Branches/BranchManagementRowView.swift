import SwiftUI

struct BranchManagementRowView: View {
    let branch: BranchInfo
    let onSwitch: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onPush: (() -> Void)?
    let onMerge: (() -> Void)?
    let onDeleteRemote: (() -> Void)?
    let onCheckoutLocally: (() -> Void)?
    var cleanupStatus: GitBranchCleanupStatus?
    var worktreeStatus: GitWorktreeCleanupStatus?
    var blockedReason: String?
    var onCleanUnit: (() -> Void)?
    var onRemoveWorktree: (() -> Void)?

    @State private var isHovered = false

    init(
        branch: BranchInfo,
        onSwitch: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onPush: (() -> Void)? = nil,
        onMerge: (() -> Void)? = nil,
        onDeleteRemote: (() -> Void)? = nil,
        onCheckoutLocally: (() -> Void)? = nil,
        cleanupStatus: GitBranchCleanupStatus? = nil,
        worktreeStatus: GitWorktreeCleanupStatus? = nil,
        blockedReason: String? = nil,
        onCleanUnit: (() -> Void)? = nil,
        onRemoveWorktree: (() -> Void)? = nil
    ) {
        self.branch = branch
        self.onSwitch = onSwitch
        self.onRename = onRename
        self.onDelete = onDelete
        self.onPush = onPush
        self.onMerge = onMerge
        self.onDeleteRemote = onDeleteRemote
        self.onCheckoutLocally = onCheckoutLocally
        self.cleanupStatus = cleanupStatus
        self.worktreeStatus = worktreeStatus
        self.blockedReason = blockedReason
        self.onCleanUnit = onCleanUnit
        self.onRemoveWorktree = onRemoveWorktree
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()

    private enum Layout {
        static let statusDotDiameter: CGFloat = 6
        static let statusSlotDiameter: CGFloat = 12
        static let minimumHeight: CGFloat = 40
    }

    var body: some View {
        rowContent
            .help(blockedReason ?? "")
    }

    private var rowContent: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            if branch.isCurrent {
                Image(systemName: "checkmark")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            } else if branch.isRemote {
                Image(systemName: "icloud")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: Layout.statusDotDiameter, height: Layout.statusDotDiameter)
                    .frame(width: Layout.statusSlotDiameter, height: Layout.statusSlotDiameter)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing / 2) {
                Text(branch.displayName)
                    .font(WorkbenchTypography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: WorkbenchMetrics.chipSpacing) {
                    trackingBadge
                    if let date = branch.lastCommitDate {
                        Text(BranchManagementRowView.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))
                            .font(WorkbenchTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let worktreeStatus {
                CleanupStatusBadgeView(status: worktreeStatus)
            } else if let cleanupStatus {
                CleanupStatusBadgeView(status: cleanupStatus)
            }

            Menu("Branch actions", systemImage: "ellipsis.circle") {
                branchActions
            }
            .labelStyle(.iconOnly)
            .font(WorkbenchTypography.body)
            .foregroundStyle(.secondary)
            .menuStyle(.borderlessButton)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            // VoiceOver reaches the same actions through the row's context menu.
            .accessibilityHidden(true)
        }
        .padding(.horizontal, WorkbenchMetrics.sectionSpacing)
        .padding(.vertical, WorkbenchMetrics.chipSpacing)
        .frame(minHeight: Layout.minimumHeight)
        .background(isHovered ? WorkbenchPalette.hoverFill() : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSwitch)
        .contextMenu {
            branchActions
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .onHover { inside in
            isHovered = inside
        }
    }

    @ViewBuilder
    private var branchActions: some View {
        if branch.isLocal {
            Button("Switch to \(branch.name)") { onSwitch() }
            Button("Rename \(branch.name)") { onRename() }
            if let onPush {
                Button("Push \(branch.name) to Remote") { onPush() }
            }
            if let onMerge {
                Button("Merge \(branch.name) into Current") { onMerge() }
            }
            if let onCleanUnit {
                Button("Clean \(branch.name)") { onCleanUnit() }
            }
            if let onRemoveWorktree {
                Button("Remove Worktree for \(branch.name)") { onRemoveWorktree() }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Text("Delete Branch \(branch.name)")
            }
        } else {
            Button("Check Out \(branch.displayName) Locally") { onCheckoutLocally?() }
            Divider()
            Button(role: .destructive) { onDeleteRemote?() } label: {
                Text("Delete Remote Branch \(branch.displayName)")
            }
        }
    }

    @ViewBuilder
    private var trackingBadge: some View {
        switch branch.trackingStatus {
        case .upToDate:
            Label("Up to date", systemImage: "equal")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.green)
        case let .ahead(count):
            Label("Ahead \(count)", systemImage: "arrow.up")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(Color.accentColor)
        case let .behind(count):
            Label("Behind \(count)", systemImage: "arrow.down")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.orange)
        case let .diverged(ahead, behind):
            Label("Diverged \(ahead)/\(behind)", systemImage: "arrow.left.arrow.right")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.orange)
        case .noRemote:
            EmptyView()
        case .unknown:
            Label("Unknown", systemImage: "questionmark")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusDotColor: Color {
        if let worktreeStatus {
            switch worktreeStatus {
            case .dirty, .locked:
                return .orange
            default:
                break
            }
        }
        switch cleanupStatus {
        case .mergedIntoDefault:
            return .green
        case .notMerged:
            return .orange
        default:
            return .secondary
        }
    }

    private var accessibilityLabel: String {
        var base = branch.displayName
        if branch.isCurrent {
            base += ", current branch"
        }
        if branch.isRemote {
            return base + ", remote branch"
        }
        base += ", " + branch.trackingStatus.description
        if let worktreeDescription {
            base += ", " + worktreeDescription
        } else if let cleanupDescription {
            base += ", " + cleanupDescription
        }
        if let blockedReason, !blockedReason.isEmpty {
            if !base.localizedStandardContains(blockedReason) {
                base += ", " + blockedReason
            }
        }
        return base
    }

    private var worktreeDescription: String? {
        guard let worktreeStatus else { return nil }
        switch worktreeStatus {
        case .dirty:
            return "worktree has uncommitted changes"
        case let .locked(reason):
            return "worktree locked: \(reason)"
        case .main:
            return "main worktree"
        case .current:
            return "current worktree"
        case .eligible:
            return "worktree eligible for cleanup"
        case let .prunable(reason):
            return "worktree prunable: \(reason)"
        case .branchNotMerged:
            return "worktree branch not merged"
        case .detached:
            return "detached worktree"
        case let .unknown(reason):
            return "worktree unknown: \(reason)"
        }
    }

    private var cleanupDescription: String? {
        switch cleanupStatus {
        case .none:
            nil
        case .mergedIntoDefault:
            "merged"
        case .notMerged:
            "not merged"
        case .protected:
            "protected"
        case .current:
            nil
        case .checkedOutElsewhere:
            "checked out in another worktree"
        case .unknown:
            "cleanup status unknown"
        }
    }
}

#Preview("Branch Management Row") {
    VStack(spacing: WorkbenchMetrics.microSpacing) {
        BranchManagementRowView(
            branch: BranchInfo(
                name: "feature/ui",
                isLocal: true,
                isRemote: false,
                isCurrent: true,
                trackingStatus: .ahead(2),
                lastCommitDate: Date().addingTimeInterval(-3600)
            ),
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: {},
            onMerge: {},
            onDeleteRemote: nil,
            onCheckoutLocally: nil,
            cleanupStatus: .mergedIntoDefault
        )
        BranchManagementRowView(
            branch: BranchInfo(
                name: "feature/dirty-worktree",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .upToDate,
                lastCommitDate: Date().addingTimeInterval(-1800)
            ),
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: {},
            onMerge: {},
            onDeleteRemote: nil,
            onCheckoutLocally: nil,
            worktreeStatus: .dirty,
            onCleanUnit: {},
            onRemoveWorktree: {}
        )
        BranchManagementRowView(
            branch: BranchInfo(
                name: "feature/stale-experiment",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: Date().addingTimeInterval(-172_800)
            ),
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: {},
            onMerge: {},
            onDeleteRemote: nil,
            onCheckoutLocally: nil,
            cleanupStatus: .notMerged
        )
        BranchManagementRowView(
            branch: BranchInfo(
                name: "feature/remote-only",
                isLocal: false,
                isRemote: true,
                isCurrent: false,
                trackingStatus: .noRemote,
                lastCommitDate: Date().addingTimeInterval(-86400)
            ),
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: nil,
            onMerge: nil,
            onDeleteRemote: {},
            onCheckoutLocally: {}
        )
        BranchManagementRowView(
            branch: BranchInfo(
                name: "feature/checkout-flow-with-very-long-descriptive-suffix-for-truncation-check",
                isLocal: true,
                isRemote: false,
                isCurrent: false,
                trackingStatus: .behind(3),
                lastCommitDate: Date().addingTimeInterval(-259_200)
            ),
            onSwitch: {},
            onRename: {},
            onDelete: {},
            onPush: nil,
            onMerge: nil,
            onDeleteRemote: nil,
            onCheckoutLocally: nil,
            worktreeStatus: .dirty,
            blockedReason: "Uncommitted changes",
            onCleanUnit: {},
            onRemoveWorktree: {}
        )
    }
    .padding()
    .frame(width: WorkbenchMetrics.sidePanelWidth)
}
