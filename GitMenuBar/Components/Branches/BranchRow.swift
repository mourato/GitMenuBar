import SwiftUI

struct BranchRowView: View {
    let branchName: String
    let isCurrentBranch: Bool
    let onTap: () -> Void
    let onMerge: (() -> Void)?
    let onDelete: (() -> Void)?
    let onRename: (() -> Void)?
    let onMergeToDefault: (() -> Void)?
    let currentBranchName: String

    init(
        branchName: String,
        isCurrentBranch: Bool,
        currentBranchName: String = "",
        onTap: @escaping () -> Void,
        onMerge: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onMergeToDefault: (() -> Void)? = nil
    ) {
        self.branchName = branchName
        self.isCurrentBranch = isCurrentBranch
        self.currentBranchName = currentBranchName
        self.onTap = onTap
        self.onMerge = onMerge
        self.onDelete = onDelete
        self.onRename = onRename
        self.onMergeToDefault = onMergeToDefault
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(branchName)
                    .font(WorkbenchTypography.body)
                Spacer()
                if isCurrentBranch {
                    Image(systemName: "checkmark")
                        .font(WorkbenchTypography.captionStrong)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(minHeight: WorkbenchMetrics.iconHitTarget)
        }
        .workbenchRow(isSelected: isCurrentBranch)
        .accessibilityLabel(isCurrentBranch ? "\(branchName), current branch" : branchName)
        .accessibilityHint("Opens branch actions.")
        .contextMenu {
            Button("Rename") {
                onRename?()
            }

            if !isCurrentBranch {
                if let onMerge {
                    Button(action: onMerge) {
                        Text("Merge into \(currentBranchName)")
                    }
                    .help("Take changes from \(branchName) and bring them into \(currentBranchName)")
                }

                if !isCurrentBranch, let onMergeToDefault {
                    Button(action: onMergeToDefault) {
                        Text("Merge into default branch")
                    }
                    .help("Switch to the default branch and merge \(branchName) into it")
                }

                Divider()

                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete Branch")
                    }
                    .help("Permanently remove the branch \(branchName)")
                }
            }
        }
    }
}

#Preview("Branch Row") {
    BranchRowView(
        branchName: "feature/popover-ui",
        isCurrentBranch: false,
        currentBranchName: "main",
        onTap: {},
        onMerge: {},
        onDelete: {},
        onRename: {}
    )
    .padding()
    .frame(width: 220)
}
