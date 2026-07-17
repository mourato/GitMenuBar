import Foundation

extension BranchManagementSheet {
    func performCleanup() {
        guard let snapshot = worktreeSnapshot else { return }
        let targets = selectedCleanupTargets
        guard !targets.isEmpty else { return }

        showCleanupConfirmation = false
        isCleanupRunning = true
        Task {
            let result = await gitManager.performCleanupAsync(targets: targets, snapshot: snapshot)
            await MainActor.run {
                isCleanupRunning = false
                selectedCleanupIDs = []
                switch result {
                case let .success(batch):
                    cleanupResultMessage = batchResultMessage(batch)
                case let .failure(error):
                    cleanupResultMessage = "Cleanup could not start: \(error.localizedDescription)"
                }
                reloadData()
            }
        }
    }

    private func batchResultMessage(_ batch: GitCleanupBatchResult) -> String {
        batch.items.map { item in
            let status: String
            switch item.status {
            case .succeeded:
                status = "completed"
            case let .skipped(reason):
                status = "skipped — \(reason)"
            case let .failed(reason):
                status = "failed — \(reason)"
            }
            return "\(item.target.title): \(status)"
        }.joined(separator: "\n")
    }
}
