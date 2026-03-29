import SwiftUI

struct CommitComposerSectionView: View {
    @Binding var commentText: String
    let isCommentFieldFocused: FocusState<Bool>.Binding
    let showsCommentField: Bool
    let primaryButtonSystemImage: String?
    let isPrimaryActionBusy: Bool
    let automaticMessageHint: String?
    let generationDisabledReason: String?
    let generationError: String?
    let primaryButtonTitle: String
    let isPrimaryButtonDisabled: Bool
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsCommentField {
                TextField("Commit message (optional)", text: $commentText, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.roundedBorder)
                    .focused(isCommentFieldFocused)
                    .accessibilityHint("Type a commit message or leave it empty to use automatic generation when available.")
            }

            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    if isPrimaryActionBusy {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let primaryButtonSystemImage {
                        Label(primaryButtonTitle, systemImage: primaryButtonSystemImage)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text(primaryButtonTitle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(isPrimaryButtonDisabled ? .gray.opacity(0.75) : nil)
            .disabled(isPrimaryButtonDisabled)
            .keyboardShortcut(.defaultAction)

            if let automaticMessageHint {
                Text(automaticMessageHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let generationDisabledReason {
                Text(generationDisabledReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let generationError {
                Text(generationError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct CommitComposerSectionPreviewContainer: View {
    @State private var message = "feat(ui): improve spacing"
    @FocusState private var isFocused: Bool
    let showsCommentField: Bool
    let automaticMessageHint: String?

    var body: some View {
        CommitComposerSectionView(
            commentText: $message,
            isCommentFieldFocused: $isFocused,
            showsCommentField: showsCommentField,
            primaryButtonSystemImage: "checkmark",
            isPrimaryActionBusy: false,
            automaticMessageHint: automaticMessageHint,
            generationDisabledReason: nil,
            generationError: nil,
            primaryButtonTitle: "Commit",
            isPrimaryButtonDisabled: false,
            onPrimaryAction: {}
        )
        .padding()
        .frame(width: 360)
    }
}

#Preview("Commit Composer") {
    CommitComposerSectionPreviewContainer(
        showsCommentField: true,
        automaticMessageHint: nil
    )
}

#Preview("Commit Composer Hidden Field") {
    CommitComposerSectionPreviewContainer(
        showsCommentField: false,
        automaticMessageHint: "Commit messages will be generated automatically."
    )
}
