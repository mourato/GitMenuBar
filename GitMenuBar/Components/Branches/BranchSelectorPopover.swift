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
                ForEach(availableBranches, id: \.self) { branch in
                    BranchRowView(
                        branchName: branch,
                        isCurrentBranch: branch == currentBranch,
                        currentBranchName: currentBranch,
                        onTap: {
                            onSelectBranch(branch)
                        },
                        onMerge: branch == currentBranch ? nil : {
                            onMergeBranch(branch)
                        },
                        onDelete: branch == currentBranch ? nil : {
                            onDeleteBranch(branch)
                        },
                        onRename: {
                            onRenameBranch(branch)
                        }
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
        .background(.regularMaterial)
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
