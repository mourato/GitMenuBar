import Foundation

struct MainMenuActionAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
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
    @Published var alert: MainMenuActionAlert?
    @Published var showSyncOptions = false

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
        gitManager.isCommitting || aiCommitCoordinator.isGenerating
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

        clearAlert()
        showSyncOptions = false

        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureTitle = shouldPushAfterCommit ? "Commit & Push Failed" : "Commit Failed"
        let message: String

        do {
            if forceAutomaticMessage || trimmedText.isEmpty {
                guard aiCommitCoordinator.isReadyForGeneration else {
                    throw NSError(
                        domain: "MainMenuActionCoordinator",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: aiCommitCoordinator.generationDisabledReason]
                    )
                }

                message = try await aiCommitCoordinator.generateMessage(scopeOverride: preferredCommitScope)
            } else {
                aiCommitCoordinator.generationError = nil
                message = trimmedText
            }
        } catch {
            publishAlert(title: failureTitle, message: error.localizedDescription)
            return .failed
        }

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

    func performSync() async -> MainMenuSyncExecutionResult {
        guard canSync else {
            return .skipped
        }

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

    func syncWithRemote(rebase: Bool) async -> MainMenuSyncExecutionResult {
        guard !isBusy else {
            return .skipped
        }

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

    private var preferredCommitScope: DiffScope {
        gitManager.stagedFiles.isEmpty ? .unstaged : .staged
    }

    private func publishAlert(title: String, message: String) {
        alert = MainMenuActionAlert(title: title, message: message)
    }

    private func commitLocally(_ message: String) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            gitManager.commitLocallyWithFallback(message) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func pushToRemote() async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            gitManager.pushToRemote { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func pullFromRemote(rebase: Bool) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            gitManager.pullFromRemote(rebase: rebase) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func refreshRepository() async {
        await withCheckedContinuation { continuation in
            gitManager.refresh {
                continuation.resume()
            }
        }
    }

    private func refreshRemoteStatus() async {
        await withCheckedContinuation { continuation in
            gitManager.checkRemoteStatus {
                continuation.resume()
            }
        }
    }
}
