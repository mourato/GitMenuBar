import Foundation

enum CommitHistoryEditMode: Equatable {
    case manual
    case aiSuggestion

    var title: String {
        switch self {
        case .manual:
            return "Edit Commit Message"
        case .aiSuggestion:
            return "Review Suggested Message"
        }
    }
}

struct CommitHistoryRewriteConfirmation: Identifiable, Equatable {
    let id = UUID()
    let commit: Commit
    let proposedMessage: String
}

@MainActor
final class CommitHistoryEditCoordinator: ObservableObject {
    @Published private(set) var editingCommit: Commit?
    @Published private(set) var editMode: CommitHistoryEditMode = .manual
    @Published private(set) var isEditorPresented = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isSaving = false
    @Published private(set) var isPublishedCommit = false
    @Published var draftMessage = ""
    @Published var inlineError: String?
    @Published var alert: MainMenuActionAlert?
    @Published var rewriteConfirmation: CommitHistoryRewriteConfirmation?

    private let gitManager: GitManager
    private let aiCommitCoordinator: AICommitCoordinator

    init(gitManager: GitManager, aiCommitCoordinator: AICommitCoordinator) {
        self.gitManager = gitManager
        self.aiCommitCoordinator = aiCommitCoordinator
    }

    func beginManualEdit(for commit: Commit) async {
        guard let isPublished = await validateCommitForEditing(commit) else {
            return
        }

        openEditor(
            for: commit,
            mode: .manual,
            draftMessage: fullMessage(for: commit),
            isPublishedCommit: isPublished
        )
    }

    func beginAIGeneratedEdit(for commit: Commit) async {
        guard let isPublished = await validateCommitForEditing(commit) else {
            return
        }

        inlineError = nil
        isPreparing = true
        defer { isPreparing = false }

        do {
            let diff = try await diffForCommit(commit.id)
            let suggestion = try await aiCommitCoordinator.generateMessage(
                forRawDiff: diff,
                scopeDescription: "Selected commit"
            )
            openEditor(
                for: commit,
                mode: .aiSuggestion,
                draftMessage: suggestion,
                isPublishedCommit: isPublished
            )
        } catch {
            publishAlert(title: "Generate Message Failed", message: error.localizedDescription)
        }
    }

    func saveDraftMessage() async -> Bool {
        guard let commit = editingCommit else {
            return false
        }

        let trimmedDraft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            inlineError = "Enter a commit message before saving."
            return false
        }

        inlineError = nil

        if isPublishedCommit {
            rewriteConfirmation = CommitHistoryRewriteConfirmation(
                commit: commit,
                proposedMessage: draftMessage
            )
            return false
        }

        return await applyRewrite(for: commit, message: draftMessage, wasPublished: false)
    }

    func confirmPublishedRewrite() async -> Bool {
        guard let confirmation = rewriteConfirmation else {
            return false
        }

        return await applyRewrite(
            for: confirmation.commit,
            message: confirmation.proposedMessage,
            wasPublished: true
        )
    }

    func dismissEditor() {
        editingCommit = nil
        editMode = .manual
        isEditorPresented = false
        isPreparing = false
        isSaving = false
        isPublishedCommit = false
        draftMessage = ""
        inlineError = nil
        rewriteConfirmation = nil
    }

    func dismissRewriteConfirmation() {
        rewriteConfirmation = nil
    }

    func clearAlert() {
        alert = nil
    }

    private func openEditor(
        for commit: Commit,
        mode: CommitHistoryEditMode,
        draftMessage: String,
        isPublishedCommit: Bool
    ) {
        editingCommit = commit
        editMode = mode
        self.draftMessage = draftMessage
        self.isPublishedCommit = isPublishedCommit
        inlineError = nil
        rewriteConfirmation = nil
        isEditorPresented = true
    }

    private func validateCommitForEditing(_ commit: Commit) async -> Bool? {
        if commit.isMergeCommit {
            publishAlert(
                title: "Editing Not Supported",
                message: "Editing merge commits is not supported yet."
            )
            return nil
        }

        if gitManager.hasUncommittedChanges() {
            publishAlert(
                title: "Clean Working Tree Required",
                message: "Commit message editing requires a clean working tree. Commit, stash, or discard local changes first."
            )
            return nil
        }

        do {
            return try await isCommitPublishedToUpstream(commit.id)
        } catch {
            publishAlert(title: "Commit Inspection Failed", message: error.localizedDescription)
            return nil
        }
    }

    private func applyRewrite(for commit: Commit, message: String, wasPublished: Bool) async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            try await rewriteCommitMessage(commitHash: commit.id, newMessage: message)
            dismissEditor()

            if wasPublished {
                publishAlert(
                    title: "Commit Message Updated",
                    message: "Local history was rewritten. Your next push may require force push."
                )
            }

            return true
        } catch {
            inlineError = error.localizedDescription
            return false
        }
    }

    private func diffForCommit(_ hash: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            gitManager.diffForCommit(hash) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func isCommitPublishedToUpstream(_ hash: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            gitManager.isCommitPublishedToUpstream(hash) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func rewriteCommitMessage(commitHash: String, newMessage: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            gitManager.rewriteCommitMessage(commitHash: commitHash, newMessage: newMessage) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func fullMessage(for commit: Commit) -> String {
        if commit.body.isEmpty {
            return commit.subject
        }

        return "\(commit.subject)\n\n\(commit.body)"
    }

    private func publishAlert(title: String, message: String) {
        alert = MainMenuActionAlert(title: title, message: message)
    }
}
