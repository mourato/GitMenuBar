import Foundation

struct MainMenuActionAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct MainMenuWhitespaceCommitPrompt: Identifiable, Equatable {
    let id = UUID()
    let rawCommentText: String
    let shouldPushAfterCommit: Bool
}

enum MainMenuCommitExecutionResult: Equatable {
    case skipped
    case committed
    case committedAndNeedsSyncOptions
    case failed

    var didCommit: Bool {
        switch self {
        case .committed, .committedAndNeedsSyncOptions:
            return true
        case .skipped, .failed:
            return false
        }
    }

    var shouldOpenPopover: Bool {
        switch self {
        case .committedAndNeedsSyncOptions, .failed:
            return true
        case .skipped, .committed:
            return false
        }
    }
}

enum MainMenuSyncExecutionResult: Equatable {
    case skipped
    case synced
    case requiresOptions
    case failed

    var shouldOpenPopover: Bool {
        switch self {
        case .requiresOptions, .failed:
            return true
        case .skipped, .synced:
            return false
        }
    }
}

@MainActor
final class MainMenuActionCoordinator: ObservableObject {
    private enum CommitMessageInputState: Equatable {
        case empty
        case whitespaceOnly(raw: String)
        case manual(trimmed: String)
    }

    @Published var alert: MainMenuActionAlert?
    @Published var showSyncOptions = false
    @Published var whitespaceCommitPrompt: MainMenuWhitespaceCommitPrompt?
    @Published private(set) var isExecutingPrimaryAction = false

    private let gitManager: GitManager
    private let aiCommitCoordinator: AICommitCoordinator

    init(gitManager: GitManager, aiCommitCoordinator: AICommitCoordinator) {
        self.gitManager = gitManager
        self.aiCommitCoordinator = aiCommitCoordinator
    }

    var hasWorkingTreeChanges: Bool {
        !gitManager.stagedFiles.isEmpty || !gitManager.changedFiles.isEmpty
    }

    var hasSyncWork: Bool {
        gitManager.isAheadOfRemote || gitManager.isRemoteAhead
    }

    var syncActionTitle: String {
        gitManager.isAheadOfRemote && !gitManager.isRemoteAhead ? "Push Changes" : "Sync Changes"
    }

    var isBusy: Bool {
        gitManager.isCommitting || aiCommitCoordinator.isGenerating || isExecutingPrimaryAction
    }

    var canAutoCommit: Bool {
        hasWorkingTreeChanges && aiCommitCoordinator.isReadyForGeneration && !isBusy
    }

    var canSync: Bool {
        hasSyncWork && !hasWorkingTreeChanges && !isBusy
    }

    func clearAlert() {
        alert = nil
    }

    func dismissWhitespaceCommitPrompt() {
        whitespaceCommitPrompt = nil
    }

    func dismissSyncOptions() {
        showSyncOptions = false
    }

    func performCommit(
        commentText: String,
        forceAutomaticMessage: Bool = false,
        shouldPushAfterCommit: Bool = false
    ) async -> MainMenuCommitExecutionResult {
        guard hasWorkingTreeChanges, !isBusy else {
            return .skipped
        }

        return await executePrimaryAction {
            clearAlert()
            showSyncOptions = false
            whitespaceCommitPrompt = nil

            let failureTitle = shouldPushAfterCommit ? "Commit & Push Failed" : "Commit Failed"

            if forceAutomaticMessage {
                return await commitUsingGeneratedMessage(
                    failureTitle: failureTitle,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
            }

            switch resolveCommitMessageInputState(commentText) {
            case .empty:
                return await commitUsingGeneratedMessage(
                    failureTitle: failureTitle,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
            case let .manual(trimmed):
                return await executeCommitFlow(
                    message: trimmed,
                    failureTitle: failureTitle,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
            case let .whitespaceOnly(raw):
                whitespaceCommitPrompt = MainMenuWhitespaceCommitPrompt(
                    rawCommentText: raw,
                    shouldPushAfterCommit: shouldPushAfterCommit
                )
                return .skipped
            }
        }
    }

    func commitUsingCurrentWhitespaceMessage(
        _ rawMessage: String,
        shouldPushAfterCommit: Bool = false
    ) async -> MainMenuCommitExecutionResult {
        guard hasWorkingTreeChanges, !isBusy else {
            return .skipped
        }

        return await executePrimaryAction {
            clearAlert()
            showSyncOptions = false
            whitespaceCommitPrompt = nil

            let failureTitle = shouldPushAfterCommit ? "Commit & Push Failed" : "Commit Failed"
            return await executeCommitFlow(
                message: rawMessage,
                failureTitle: failureTitle,
                shouldPushAfterCommit: shouldPushAfterCommit
            )
        }
    }

    func commitByGeneratingMessage(
        afterDiscardingWhitespace _: String,
        shouldPushAfterCommit: Bool = false
    ) async -> MainMenuCommitExecutionResult {
        guard hasWorkingTreeChanges, !isBusy else {
            return .skipped
        }

        return await executePrimaryAction {
            clearAlert()
            showSyncOptions = false
            whitespaceCommitPrompt = nil

            let failureTitle = shouldPushAfterCommit ? "Commit & Push Failed" : "Commit Failed"
            return await commitUsingGeneratedMessage(
                failureTitle: failureTitle,
                shouldPushAfterCommit: shouldPushAfterCommit
            )
        }
    }

    func performSync() async -> MainMenuSyncExecutionResult {
        guard canSync else {
            return .skipped
        }

        return await executePrimaryAction {
            clearAlert()
            showSyncOptions = false

            if gitManager.isRemoteAhead {
                showSyncOptions = true
                return .requiresOptions
            }

            let pushResult = await pushToRemote()
            guard case .success = pushResult else {
                if case let .failure(error) = pushResult {
                    publishAlert(title: "Sync Failed", message: error.localizedDescription)
                }
                return .failed
            }

            await refreshRepository()
            await refreshRemoteStatus()
            return .synced
        }
    }

    func syncWithRemote(rebase: Bool) async -> MainMenuSyncExecutionResult {
        guard !isBusy else {
            return .skipped
        }

        return await executePrimaryAction {
            clearAlert()
            showSyncOptions = false

            let pullResult = await pullFromRemote(rebase: rebase)
            guard case .success = pullResult else {
                if case let .failure(error) = pullResult {
                    publishAlert(title: "Sync Failed", message: error.localizedDescription)
                }
                return .failed
            }

            let pushResult = await pushToRemote()
            guard case .success = pushResult else {
                if case let .failure(error) = pushResult {
                    publishAlert(title: "Push Failed", message: error.localizedDescription)
                }
                return .failed
            }

            await refreshRepository()
            return .synced
        }
    }

    private var preferredCommitScope: DiffScope {
        gitManager.stagedFiles.isEmpty ? .unstaged : .staged
    }

    private func resolveCommitMessageInputState(_ rawInput: String) -> CommitMessageInputState {
        if rawInput.isEmpty {
            return .empty
        }

        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .whitespaceOnly(raw: rawInput)
        }

        return .manual(trimmed: trimmed)
    }

    private func publishAlert(title: String, message: String) {
        alert = MainMenuActionAlert(title: title, message: message)
    }

    private func commitUsingGeneratedMessage(
        failureTitle: String,
        shouldPushAfterCommit: Bool
    ) async -> MainMenuCommitExecutionResult {
        do {
            guard aiCommitCoordinator.isReadyForGeneration else {
                throw NSError(
                    domain: "MainMenuActionCoordinator",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: aiCommitCoordinator.generationDisabledReason]
                )
            }

            let message = try await aiCommitCoordinator.generateMessage(scopeOverride: preferredCommitScope)
            return await executeCommitFlow(
                message: message,
                failureTitle: failureTitle,
                shouldPushAfterCommit: shouldPushAfterCommit
            )
        } catch {
            publishAlert(title: failureTitle, message: error.localizedDescription)
            return .failed
        }
    }

    private func executeCommitFlow(
        message: String,
        failureTitle: String,
        shouldPushAfterCommit: Bool
    ) async -> MainMenuCommitExecutionResult {
        aiCommitCoordinator.generationError = nil

        let commitResult = await commitLocally(message)
        guard case .success = commitResult else {
            if case let .failure(error) = commitResult {
                publishAlert(title: failureTitle, message: error.localizedDescription)
            }
            return .failed
        }

        await refreshRepository()
        await refreshRemoteStatus()

        guard shouldPushAfterCommit else {
            return .committed
        }

        if gitManager.isRemoteAhead {
            showSyncOptions = true
            return .committedAndNeedsSyncOptions
        }

        let pushResult = await pushToRemote()
        guard case .success = pushResult else {
            if case let .failure(error) = pushResult {
                publishAlert(title: failureTitle, message: error.localizedDescription)
            }
            return .failed
        }

        await refreshRepository()
        await refreshRemoteStatus()
        return .committed
    }

    private func executePrimaryAction<T>(_ operation: () async -> T) async -> T {
        isExecutingPrimaryAction = true
        defer {
            isExecutingPrimaryAction = false
        }
        return await operation()
    }

    private func commitLocally(_ message: String) async -> Result<Void, Error> {
        await gitManager.commitLocallyWithFallbackAsync(message)
    }

    private func pushToRemote() async -> Result<Void, Error> {
        await gitManager.pushToRemoteAsync()
    }

    private func pullFromRemote(rebase: Bool) async -> Result<Void, Error> {
        await gitManager.pullFromRemoteAsync(rebase: rebase)
    }

    private func refreshRepository(includeReflogHistory: Bool = false) async {
        await gitManager.refreshAsync(includeReflogHistory: includeReflogHistory)
    }

    private func refreshRemoteStatus() async {
        await gitManager.checkRemoteStatusAsync()
    }
}
