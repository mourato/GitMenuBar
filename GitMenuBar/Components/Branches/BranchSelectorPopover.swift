import AppKit
import SwiftUI

struct BranchSelectorPopoverView: View {
    let isDetachedHead: Bool
    let isRemoteAhead: Bool
    let behindCount: Int
    let availableBranches: [String]
    let currentBranch: String
    let onCreateBranchFromDetached: () -> Void
    let onQuickPull: () -> Void
    let onSelectBranch: (String) -> Void
    let onMergeBranch: (String) -> Void
    let onDeleteBranch: (String) -> Void
    let onRenameBranch: (String) -> Void
    let onNewBranch: () -> Void

    private var branchRows: [BranchMenuRowAdapter] {
        availableBranches.map {
            BranchMenuRowAdapter(branchName: $0, currentBranchName: currentBranch)
        }
    }

    var body: some View {
        List {
            if isDetachedHead {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Detached HEAD State", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text("You aren't on a branch. Edits made here might be hard to find later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(action: onCreateBranchFromDetached) {
                            Label("Create Branch from Here…", systemImage: "plus.branch")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }

            if isRemoteAhead {
                Section {
                    Button(action: onQuickPull) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Pull \(behindCount) commit\(behindCount == 1 ? "" : "s")", systemImage: "arrow.down.circle.fill")
                            Text("Update the current branch from remote.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Branches") {
                ForEach(branchRows) { row in
                    let mergeAction = row.canMerge ? { onMergeBranch(row.branchName) } : nil
                    let deleteAction = row.canDelete ? { onDeleteBranch(row.branchName) } : nil
                    let renameAction = row.canRename ? { onRenameBranch(row.branchName) } : nil

                    BranchRowView(
                        branchName: row.branchName,
                        isCurrentBranch: row.isCurrentBranch,
                        currentBranchName: row.currentBranchName,
                        onTap: {
                            onSelectBranch(row.branchName)
                        },
                        onMerge: mergeAction,
                        onDelete: deleteAction,
                        onRename: renameAction
                    )
                }
            }

            Section {
                Button(action: onNewBranch) {
                    Label("New Branch…", systemImage: "plus")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .macPanelSurface()
        .frame(width: 260, height: 320)
    }
}

#Preview("Branch Selector") {
    BranchSelectorPopoverView(
        isDetachedHead: false,
        isRemoteAhead: true,
        behindCount: 2,
        availableBranches: ["main", "feature/ui", "bugfix/sync"],
        currentBranch: "feature/ui",
        onCreateBranchFromDetached: {},
        onQuickPull: {},
        onSelectBranch: { _ in },
        onMergeBranch: { _ in },
        onDeleteBranch: { _ in },
        onRenameBranch: { _ in },
        onNewBranch: {}
    )
}
