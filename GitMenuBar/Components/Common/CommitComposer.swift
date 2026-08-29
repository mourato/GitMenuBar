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
    let automaticRetryAvailable: Bool
    let isFallbackModelAvailable: Bool
    let primaryButtonTitle: String
    let isPrimaryButtonDisabled: Bool
    let canShowSplitCommits: Bool
    let onPrimaryAction: () -> Void
    let onSplitCommits: () -> Void
    let onRetryGeneration: () -> Void
    let onUseFallbackModel: () -> Void
    let operationStatus: MainMenuOperationStatus?

    @State private var retryCountdown = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsCommentField {
                TextField("Commit message (optional)", text: $commentText, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
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
            .primaryActionLayout(
                canShowSplitCommits: canShowSplitCommits,
                onSplitCommits: onSplitCommits,
                isPrimaryButtonDisabled: isPrimaryButtonDisabled
            )

            if let operationStatus {
                HStack(spacing: 8) {
                    if let progress = operationStatus.progress {
                        ProgressView(value: progress, total: 1)
                            .frame(width: 80)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(operationStatus.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(operationStatus.accessibilityLabel)
            }

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
                VStack(alignment: .leading, spacing: 6) {
                    Text(generationError)
                        .font(.caption)
                        .foregroundColor(.red)

                    HStack(spacing: WorkbenchMetrics.compactSpacing) {
                        Button(automaticRetryAvailable ? "Retry (\(retryCountdown)s)" : "Retry", action: onRetryGeneration)
                            .workbenchSecondary()
                            .controlSize(.large)

                        Button("Use Fallback Model", action: onUseFallbackModel)
                            .workbenchSecondary()
                            .controlSize(.large)
                            .disabled(!isFallbackModelAvailable)
                    }

                    if !isFallbackModelAvailable {
                        Text("Configure a fallback model in Settings.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.bottom, 8)
        .task(id: retryTaskID) {
            guard automaticRetryAvailable, generationError != nil else { return }

            for countdown in stride(from: 10, through: 1, by: -1) {
                retryCountdown = countdown
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            onRetryGeneration()
        }
    }

    private var retryTaskID: String {
        "\(generationError ?? "")-\(automaticRetryAvailable)"
    }
}

private extension View {
    @ViewBuilder
    func primaryActionLayout(
        canShowSplitCommits: Bool,
        onSplitCommits: @escaping () -> Void,
        isPrimaryButtonDisabled: Bool
    ) -> some View {
        if canShowSplitCommits {
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                self
                    .frame(maxWidth: .infinity)
                    .workbenchPrimary(isMuted: isPrimaryButtonDisabled)
                    .disabled(isPrimaryButtonDisabled)
                    .keyboardShortcut(.defaultAction)

                Button(action: onSplitCommits) {
                    Label("Split", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.large)
                .workbenchSecondary()
                .accessibilityLabel("Split into atomic commits")
                .help("Group changes into logical commits")
            }
        } else {
            frame(maxWidth: .infinity)
                .workbenchPrimary(isMuted: isPrimaryButtonDisabled)
                .disabled(isPrimaryButtonDisabled)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct CommitComposerSectionPreviewContainer: View {
    @State private var message = "feat(ui): improve spacing"
    @FocusState private var isFocused: Bool
    let showsCommentField: Bool
    let automaticMessageHint: String?
    let canShowSplitCommits: Bool

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
            automaticRetryAvailable: false,
            isFallbackModelAvailable: false,
            primaryButtonTitle: "Commit",
            isPrimaryButtonDisabled: false,
            canShowSplitCommits: canShowSplitCommits,
            onPrimaryAction: {},
            onSplitCommits: {},
            onRetryGeneration: {},
            onUseFallbackModel: {},
            operationStatus: nil
        )
        .padding()
        .frame(width: 360)
    }
}

#Preview("Commit Composer") {
    CommitComposerSectionPreviewContainer(
        showsCommentField: true,
        automaticMessageHint: nil,
        canShowSplitCommits: true
    )
}

#Preview("Commit Composer Hidden Field") {
    CommitComposerSectionPreviewContainer(
        showsCommentField: false,
        automaticMessageHint: "Commit messages will be generated automatically.",
        canShowSplitCommits: false
    )
}
