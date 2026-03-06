import SwiftUI

struct CommitComposerSectionView: View {
    @Binding var commentText: String
    let isCommentFieldFocused: FocusState<Bool>.Binding
    let hasWorkingTreeChanges: Bool
    let isGenerating: Bool
    let isReadyForGeneration: Bool
    let generationDisabledReason: String
    let generationError: String?
    let primaryButtonTitle: String
    let isPrimaryButtonDisabled: Bool
    let onGenerateMessage: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                TextField("Message", text: $commentText, axis: .vertical)
                    .font(.system(size: 13))
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.plain)
                    .padding(.leading, 14)
                    .padding(.trailing, 48)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .focused(isCommentFieldFocused)

                Button(action: onGenerateMessage) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(6)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 7)
                .padding(.trailing, 8)
                .disabled(!isReadyForGeneration || isGenerating || !hasWorkingTreeChanges)
                .help(
                    isReadyForGeneration
                        ? "Generate commit message from staged files, or changes when nothing is staged."
                        : generationDisabledReason
                )
            }

            Button(action: onPrimaryAction) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(isPrimaryButtonDisabled)

            if !isReadyForGeneration {
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
            hasWorkingTreeChanges: true,
            isGenerating: false,
            isReadyForGeneration: true,
            generationDisabledReason: "Configure an AI provider in Settings.",
            generationError: nil,
            primaryButtonTitle: "Commit",
            isPrimaryButtonDisabled: false,
            onGenerateMessage: {},
            onPrimaryAction: {}
        )
        .padding()
        .frame(width: 360)
    }
}

#Preview("Commit Composer") {
    CommitComposerSectionPreviewContainer()
}
