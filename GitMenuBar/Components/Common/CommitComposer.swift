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
    let commitFileCount: Int
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

            primaryButtonContent
                .primaryActionLayout(
                    canShowSplitCommits: canShowSplitCommits,
                    onPrimaryAction: onPrimaryAction,
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

    private var primaryButtonContent: some View {
        HStack(spacing: 8) {
            if isPrimaryActionBusy {
                ProgressView()
                    .controlSize(.small)
            }

            if let primaryButtonSystemImage {
                Label(resolvedPrimaryButtonTitle, systemImage: primaryButtonSystemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(resolvedPrimaryButtonTitle)
            }
        }
    }

    private var resolvedPrimaryButtonTitle: String {
        guard primaryButtonTitle == "Commit", !isPrimaryActionBusy else {
            return primaryButtonTitle
        }

        let fileLabel = commitFileCount == 1 ? "file" : "files"
        return "Commit \(commitFileCount) \(fileLabel)"
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
    func primaryActionLayout(
        canShowSplitCommits: Bool,
        onPrimaryAction: @escaping () -> Void,
        onSplitCommits: @escaping () -> Void,
        isPrimaryButtonDisabled: Bool
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    self
                    Spacer(minLength: WorkbenchMetrics.compactSpacing)
                    Text("⌘↩")
                        .font(WorkbenchTypography.captionStrong)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, WorkbenchMetrics.compactSpacing)
            }
            .buttonStyle(CommitSplitSegmentStyle(isMuted: isPrimaryButtonDisabled))
            .keyboardShortcut(.defaultAction)

            if canShowSplitCommits {
                Divider()
                    .overlay(.white.opacity(0.35))
                    .padding(.vertical, 6)

                Menu {
                    Button(action: onSplitCommits) {
                        Label("Split with AI", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: WorkbenchMetrics.iconHitTarget)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(CommitSplitSegmentStyle(isMuted: isPrimaryButtonDisabled))
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("More commit actions")
                .help("Split changes into commits with AI")
            }
        }
        .frame(height: 32)
        .background(
            isPrimaryButtonDisabled ? Color.gray.opacity(0.75) : Color.accentColor,
            in: Capsule()
        )
        .clipShape(Capsule())
        .disabled(isPrimaryButtonDisabled)
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
            commitFileCount: 3,
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

/// One segment of the commit split button; the shared capsule background
/// comes from the container so both segments read as a single control.
private struct CommitSplitSegmentStyle: ButtonStyle {
    let isMuted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(configuration.isPressed ? 0.15 : 0))
            .opacity(isMuted ? 0.7 : 1)
    }
}
