import AppKit
import SwiftUI

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
            if inside, !isCurrentCommit {
                NSCursor.pointingHand.push()
            } else if !inside {
                NSCursor.pop()
            }
        }
    }
}

#Preview("Commit Row") {
    CommitRowView(
        commit: Commit(
            id: "abc123",
            message: "feat(ui): improve composer spacing",
            date: "Today",
            author: "bot"
        ),
        isCurrentCommit: false,
        isFutureCommit: false,
        onTap: {}
    )
    .padding()
    .frame(width: 360)
}
