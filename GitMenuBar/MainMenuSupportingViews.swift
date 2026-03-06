//
//  MainMenuSupportingViews.swift
//  GitMenuBar
//

import AppKit
import SwiftUI

/// Separate view for commit row to handle hover state
struct CommitRowView: View {
    let commit: Commit
    let isCurrentCommit: Bool
    let isFutureCommit: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Text(commit.message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(isFutureCommit ? .blue : .primary)

                Spacer(minLength: 0)

                if isFutureCommit {
                    Text("Future")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                        .fixedSize()
                }

                Text(commit.date)
                    .font(.system(size: 10))
                    .foregroundColor(isFutureCommit ? .blue.opacity(0.7) : .secondary)
                    .fixedSize()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(
            isCurrentCommit ? Color.primary.opacity(0.05) :
                isHovered ? Color.primary.opacity(0.03) : Color.clear
        )
        .cornerRadius(4)
        .onHover { inside in
            isHovered = inside
            if inside && !isCurrentCommit {
                NSCursor.pointingHand.push()
            } else if !inside {
                NSCursor.pop()
            }
        }
    }
}

/// Separate view for branch row with custom hover state and context menu
struct BranchRowView: View {
    let branchName: String
    let isCurrentBranch: Bool
    let onTap: () -> Void
    let onMerge: (() -> Void)?
    let onDelete: (() -> Void)?
    let onRename: (() -> Void)?
    let currentBranchName: String

    @State private var isHovered = false

    init(branchName: String, isCurrentBranch: Bool, currentBranchName: String = "", onTap: @escaping () -> Void, onMerge: (() -> Void)? = nil, onDelete: (() -> Void)? = nil, onRename: (() -> Void)? = nil) {
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
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            if isCurrentBranch {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            Button("Rename") {
                onRename?()
            }

            if !isCurrentBranch {
                if let onMerge = onMerge {
                    Button {
                        onMerge()
                    } label: {
                        Text("Merge into \(currentBranchName)")
                    }
                    .help("Take changes from \(branchName) and bring them into \(currentBranchName)")
                }

                Divider()

                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
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

struct NewBranchButton: View {
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
            Text("New Branch")
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
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

/// Separate view for recent path row to handle hover state
struct RecentPathRowView: View {
    let displayText: String
    let fullPath: String
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(displayText)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(fullPath) // Show full path on hover
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.gray.opacity(0.15) : Color.gray.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
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

struct WorkingTreeFileRowView: View {
    let file: WorkingTreeFile
    let actionIcon: String
    let actionHelp: String
    let onAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(file.path)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text("+\(file.lineDiff.added)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(file.lineDiff.added > 0 ? .green : .secondary)
                Text("-\(file.lineDiff.removed)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(file.lineDiff.removed > 0 ? .red : .secondary)
            }

            Button(action: onAction) {
                Image(systemName: actionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(actionHelp)
            .opacity(isHovered ? 1 : 0)
            .frame(width: 16)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
