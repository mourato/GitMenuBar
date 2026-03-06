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
        VStack(alignment: .leading, spacing: 0) {
            if isDetachedHead {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Detached HEAD State")
                            .font(.system(size: 11, weight: .bold))
                    }

                    Text("You aren't on a branch. Edits made here might be hard to find later.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onCreateBranchFromDetached) {
                        Label("Create Branch from here...", systemImage: "plus.branch")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }
                .padding(12)
                .background(Color.red.opacity(0.05))

                Divider()
            }

            Text("Branches")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 10)

            if isRemoteAhead {
                Button(action: onQuickPull) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pull \(behindCount) commits")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Update current branch from remote")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.1))
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                Divider()
                    .padding(.horizontal, 10)
            }

            ScrollView {
                VStack(spacing: 0) {
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
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)

            Divider()
                .padding(.horizontal, 10)

            NewBranchButton(onTap: onNewBranch)
        }
        .frame(width: 200)
        .padding(.bottom, 4)
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
