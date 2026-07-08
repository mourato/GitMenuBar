import AppKit
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

    @State private var isHovered = false

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            if branch.isCurrent {
                Image(systemName: "checkmark")
                    .font(MacChromeTypography.captionStrong)
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: branch.isRemote ? "icloud" : "arrow.triangle.branch")
                    .font(MacChromeTypography.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(branch.displayName)
                    .font(MacChromeTypography.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    trackingBadge
                    if let date = branch.lastCommitDate {
                        Text(BranchManagementRowView.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))
                            .font(MacChromeTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if branch.isLocal {
                Menu {
                    Button("Switch to \(branch.name)") { onSwitch() }
                    Button("Rename…") { onRename() }
                    if let onPush {
                        Button("Push to Remote") { onPush() }
                    }
                    if let onMerge {
                        Button("Merge into Current") { onMerge() }
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Text("Delete Branch")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(MacChromeTypography.body)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .opacity(isHovered ? 1 : 0.4)
            } else {
                Menu {
                    Button("Checkout Locally") { onCheckoutLocally?() }
                    Divider()
                    Button(role: .destructive) { onDeleteRemote?() } label: {
                        Text("Delete Remote Branch")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(MacChromeTypography.body)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .opacity(isHovered ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
        .background(isHovered ? MacChromePalette.hoverFill() : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSwitch)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private var trackingBadge: some View {
        switch branch.trackingStatus {
        case .upToDate:
            Label("Up to date", systemImage: "equal")
                .font(MacChromeTypography.caption)
                .foregroundStyle(.green)
        case let .ahead(count):
            Label("Ahead \(count)", systemImage: "arrow.up")
                .font(MacChromeTypography.caption)
                .foregroundStyle(Color.accentColor)
        case let .behind(count):
            Label("Behind \(count)", systemImage: "arrow.down")
                .font(MacChromeTypography.caption)
                .foregroundStyle(.orange)
        case let .diverged(ahead, behind):
            Label("Diverged \(ahead)/\(behind)", systemImage: "arrow.left.arrow.right")
                .font(MacChromeTypography.caption)
                .foregroundStyle(.orange)
        case .noRemote:
            Label("No upstream", systemImage: "dot")
                .font(MacChromeTypography.caption)
                .foregroundStyle(.secondary)
        case .unknown:
            Label("Unknown", systemImage: "questionmark")
                .font(MacChromeTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        var base = branch.displayName
        if branch.isCurrent {
            base += ", current branch"
        }
        return base + ", " + branch.trackingStatus.description
    }
}

#Preview("Branch Management Row") {
    VStack(spacing: 4) {
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
            onCheckoutLocally: nil
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
    }
    .padding()
    .frame(width: 360)
}
