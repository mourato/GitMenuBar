import SwiftUI

struct CommitMessageEditorSheet: View {
    let title: String
    let commit: Commit
    @Binding var message: String
    let isPublishedCommit: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isMessageEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Commit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Text("\(commit.shortHash) • \(commit.subject)")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            if isPublishedCommit {
                Text("This commit already exists on the remote. Saving will rewrite local history and may require force push.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit Message")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                TextEditor(text: $message)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(Color.black.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($isMessageEditorFocused)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(action: onSave) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isMessageEditorFocused = true
            }
        }
    }
}

private struct CommitMessageEditorSheetPreviewContainer: View {
    @State private var message = "feat(history): reword old commit\n\n- Clarify the original summary"

    var body: some View {
        CommitMessageEditorSheet(
            title: "Review Suggested Message",
            commit: Commit(
                id: "abcdef1234567890",
                shortHash: "abcdef1",
                subject: "feat: old message",
                body: "",
                authorName: "Renato",
                authorEmail: "renato@example.com",
                committedAt: Date(),
                stats: CommitStats(filesChanged: 1, insertions: 1, deletions: 0),
                changedFiles: []
            ),
            message: $message,
            isPublishedCommit: true,
            isSaving: false,
            errorMessage: nil,
            onCancel: {},
            onSave: {}
        )
    }
}

#Preview("Commit Message Editor Sheet") {
    CommitMessageEditorSheetPreviewContainer()
}
