import SwiftUI

struct CommitWorkflowView: View {
    @Binding var commentText: String
    var isCommentFieldFocused: FocusState<Bool>.Binding
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
    let onDidCommit: () -> Void
    let onRequestFocus: () -> Void
    let focusCommitFieldToken: Int

    @ObservedObject var actionCoordinator: MainMenuActionCoordinator
    @ObservedObject var commitHistoryEditCoordinator: CommitHistoryEditCoordinator

    var body: some View {
        CommitComposerSectionView(
            commentText: $commentText,
            isCommentFieldFocused: isCommentFieldFocused,
            showsCommentField: showsCommentField,
            primaryButtonSystemImage: primaryButtonSystemImage,
            isPrimaryActionBusy: isPrimaryActionBusy,
            automaticMessageHint: automaticMessageHint,
            generationDisabledReason: generationDisabledReason,
            generationError: generationError,
            automaticRetryAvailable: automaticRetryAvailable,
            isFallbackModelAvailable: isFallbackModelAvailable,
            primaryButtonTitle: primaryButtonTitle,
            isPrimaryButtonDisabled: isPrimaryButtonDisabled,
            canShowSplitCommits: canShowSplitCommits,
            onPrimaryAction: onPrimaryAction,
            onSplitCommits: onSplitCommits,
            onRetryGeneration: onRetryGeneration,
            onUseFallbackModel: onUseFallbackModel,
            operationStatus: actionCoordinator.operationStatus
        )
        .onAppear {
            onRequestFocus()
        }
        .onChange(of: focusCommitFieldToken) { _ in
            onRequestFocus()
        }
        .alert(item: $commitHistoryEditCoordinator.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text("OK")) {
                    commitHistoryEditCoordinator.clearAlert()
                }
            )
        }
        .confirmationDialog(
            "Commit message contains only spaces",
            isPresented: .init(
                get: { actionCoordinator.whitespaceCommitPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        actionCoordinator.dismissWhitespaceCommitPrompt()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let prompt = actionCoordinator.whitespaceCommitPrompt {
                Button("Commit As Typed") {
                    Task {
                        let result = await actionCoordinator.commitUsingCurrentWhitespaceMessage(
                            prompt.rawCommentText,
                            shouldPushAfterCommit: prompt.shouldPushAfterCommit
                        )
                        if result.didCommit {
                            commentText = ""
                            onDidCommit()
                        }
                    }
                }

                Button("Generate Message") {
                    Task {
                        let result = await actionCoordinator.commitByGeneratingMessage(
                            afterDiscardingWhitespace: prompt.rawCommentText,
                            shouldPushAfterCommit: prompt.shouldPushAfterCommit
                        )
                        if result.didCommit {
                            commentText = ""
                            onDidCommit()
                        }
                    }
                }
            }

            Button("Cancel", role: .cancel) {
                actionCoordinator.dismissWhitespaceCommitPrompt()
            }
        } message: {
            Text(
                "The current message has no visible text. You can cancel, commit with the current text, "
                    + "or ignore it and generate a message automatically."
            )
        }
        .confirmationDialog(
            "Rewrite Published Commit?",
            isPresented: .init(
                get: { commitHistoryEditCoordinator.rewriteConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        commitHistoryEditCoordinator.dismissRewriteConfirmation()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Rewrite Commit", role: .destructive) {
                Task {
                    await commitHistoryEditCoordinator.confirmPublishedRewrite()
                }
            }

            Button("Cancel", role: .cancel) {
                commitHistoryEditCoordinator.dismissRewriteConfirmation()
            }
        } message: {
            Text(
                "This commit already exists on the remote. Rewriting it changes local history "
                    + "and your next push may require force push."
            )
        }
    }
}

#Preview("Commit Workflow") {
    MainMenuPreviewHarness {
        CommitWorkflowPreviewContent()
    }
}

private struct CommitWorkflowPreviewContent: View {
    @EnvironmentObject private var actionCoordinator: MainMenuActionCoordinator
    @EnvironmentObject private var commitHistoryEditCoordinator: CommitHistoryEditCoordinator
    @State private var message = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        CommitWorkflowView(
            commentText: $message,
            isCommentFieldFocused: $isFocused,
            showsCommentField: true,
            primaryButtonSystemImage: "checkmark",
            isPrimaryActionBusy: false,
            automaticMessageHint: nil,
            generationDisabledReason: nil,
            generationError: nil,
            automaticRetryAvailable: false,
            isFallbackModelAvailable: false,
            primaryButtonTitle: "Commit",
            isPrimaryButtonDisabled: false,
            canShowSplitCommits: true,
            onPrimaryAction: {},
            onSplitCommits: {},
            onRetryGeneration: {},
            onUseFallbackModel: {},
            onDidCommit: {},
            onRequestFocus: {},
            focusCommitFieldToken: 0,
            actionCoordinator: actionCoordinator,
            commitHistoryEditCoordinator: commitHistoryEditCoordinator
        )
        .padding()
        .frame(width: 360)
    }
}
