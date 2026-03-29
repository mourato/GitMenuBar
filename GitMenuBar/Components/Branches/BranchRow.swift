import AppKit
import SwiftUI

struct BranchRowView: View {
    let branchName: String
    let isCurrentBranch: Bool
    let onTap: () -> Void
    let onMerge: (() -> Void)?
    let onDelete: (() -> Void)?
    let onRename: (() -> Void)?
    let currentBranchName: String

    @State private var isHovered = false

    init(
        branchName: String,
        isCurrentBranch: Bool,
        currentBranchName: String = "",
        onTap: @escaping () -> Void,
        onMerge: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil
    ) {
        self.branchName = branchName
        self.isCurrentBranch = isCurrentBranch
        self.currentBranchName = currentBranchName
        self.onTap = onTap
        self.onMerge = onMerge
        self.onDelete = onDelete
        self.onRename = onRename
    }

    var body: some View {
        HStack {
            Text(branchName)
                .font(MacChromeTypography.body)
            Spacer()
            if isCurrentBranch {
                Image(systemName: "checkmark")
                    .font(MacChromeTypography.captionStrong)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .background(isHovered ? MacChromePalette.hoverFill() : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: MacChromeMetrics.rowCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
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

                Divider()

                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete Branch")
                    }
                    .help("Permanently remove the branch \(branchName)")
                }
            }
        }
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
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
