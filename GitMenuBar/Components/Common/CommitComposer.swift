import SwiftUI

struct CommitComposerSectionView: View {
    @Binding var commentText: String
    let isCommentFieldFocused: FocusState<Bool>.Binding
    let primaryButtonSystemImage: String?
    let isPrimaryActionBusy: Bool
    let generationDisabledReason: String?
    let generationError: String?
    let primaryButtonTitle: String
    let isPrimaryButtonDisabled: Bool
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Commit message (optional)", text: $commentText, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .padding(.leading, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused(isCommentFieldFocused)

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

            if let generationDisabledReason {
                Text(generationDisabledReason)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else if let generationError {
                Text(generationError)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct CommitComposerSectionPreviewContainer: View {
    @State private var message = "feat(ui): improve spacing"
    @FocusState private var isFocused: Bool

    var body: some View {
        CommitComposerSectionView(
            commentText: $message,
            isCommentFieldFocused: $isFocused,
            primaryButtonSystemImage: "checkmark",
            isPrimaryActionBusy: false,
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
    CommitComposerSectionPreviewContainer()
}
