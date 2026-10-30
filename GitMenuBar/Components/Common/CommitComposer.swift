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
            } else {
                GeneratedMessageCard(
                    commentText: $commentText,
                    isCommentFieldFocused: isCommentFieldFocused,
                    automaticMessageHint: automaticMessageHint
                )
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

                    Spacer(minLength: WorkbenchMetrics.compactSpacing)

                    Text("⌘↩")
                        .font(WorkbenchTypography.captionStrong)
                        .accessibilityHidden(true)
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

            if let generationDisabledReason {
                Text(generationDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let generationError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(generationError)
                        .font(.caption)
                        .foregroundStyle(.red)

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
                            .foregroundStyle(.secondary)
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

private struct GeneratedMessageCard: View {
    @Binding var commentText: String
    let isCommentFieldFocused: FocusState<Bool>.Binding
    let automaticMessageHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Label("Generated message", systemImage: "sparkles")
                .font(WorkbenchTypography.captionStrong)
                .foregroundStyle(Color.accentColor)

            TextField(
                "",
                text: messageBinding,
                prompt: Text(messagePlaceholder),
                axis: .vertical
            )
            .lineLimit(1 ... 4)
            .textFieldStyle(.plain)
            .font(WorkbenchTypography.body)
            .autocorrectionDisabled(true)
            .focused(isCommentFieldFocused)
            .accessibilityLabel("Commit message")
            .accessibilityHint("Edit the generated commit message.")

            Text("Click to edit")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(WorkbenchMetrics.compactSpacing)
        .workbenchPanelSurface(cornerRadius: WorkbenchMetrics.cornerRadius, material: .thin)
    }

    private var messageBinding: Binding<String> {
        Binding(
            get: {
                if !commentText.isEmpty {
                    return commentText
                }
                return generatedMessagePreview ?? ""
            },
            set: { commentText = $0 }
        )
    }

    private var generatedMessagePreview: String? {
        guard let automaticMessageHint else { return nil }

        let trimmedHint = automaticMessageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHint.isEmpty,
              trimmedHint != "Commit messages will be generated automatically.",
              !trimmedHint.hasPrefix("Automatic commit generation is unavailable.")
        else {
            return nil
        }

        return trimmedHint
    }

    private var messagePlaceholder: String {
        if automaticMessageHint?.hasPrefix("Automatic commit generation is unavailable.") == true {
            return "Enter a message to commit manually."
        }

        return "A message will be generated when you commit."
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
            HStack(spacing: 0) {
                self
                    .frame(maxWidth: .infinity)
                    .workbenchPrimary(isMuted: isPrimaryButtonDisabled)
                    .disabled(isPrimaryButtonDisabled)
                    .keyboardShortcut(.defaultAction)

                Menu {
                    Button(action: onSplitCommits) {
                        Label("Split with AI", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: WorkbenchMetrics.iconHitTarget)
                }
                .controlSize(.large)
                .menuIndicator(.hidden)
                .workbenchPrimary(isMuted: isPrimaryButtonDisabled)
                .accessibilityLabel("Split commit actions")
                .help("Choose a split commit action")
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
    @State private var message: String
    @FocusState private var isFocused: Bool
    let showsCommentField: Bool
    let automaticMessageHint: String?
    let canShowSplitCommits: Bool

    init(
        initialMessage: String,
        showsCommentField: Bool,
        automaticMessageHint: String?,
        canShowSplitCommits: Bool
    ) {
        _message = State(initialValue: initialMessage)
        self.showsCommentField = showsCommentField
        self.automaticMessageHint = automaticMessageHint
        self.canShowSplitCommits = canShowSplitCommits
    }

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
        initialMessage: "feat(ui): improve spacing",
        showsCommentField: true,
        automaticMessageHint: nil,
        canShowSplitCommits: true
    )
}

#Preview("Generated Message Card") {
    CommitComposerSectionPreviewContainer(
        initialMessage: "feat(ui): improve spacing",
        showsCommentField: false,
        automaticMessageHint: "Commit messages will be generated automatically.",
        canShowSplitCommits: false
    )
}

#Preview("Generated Message Placeholder") {
    CommitComposerSectionPreviewContainer(
        initialMessage: "",
        showsCommentField: false,
        automaticMessageHint: "Commit messages will be generated automatically.",
        canShowSplitCommits: false
    )
}
