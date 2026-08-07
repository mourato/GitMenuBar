import Foundation

extension BranchManagementSheet {
    func performCleanup() {
        guard let snapshot = worktreeSnapshot else { return }
        let units = selectedCleanupUnits
        guard !units.isEmpty else { return }

        showCleanupConfirmation = false
        isCleanupRunning = true
        Task {
            let result = await gitManager.performCleanupAsync(units: units, snapshot: snapshot)
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
            let status = switch item.status {
            case .succeeded:
                "completed"
            case let .partiallySucceeded(reason):
                "partially completed — \(reason)"
            case let .skipped(reason):
                "skipped — \(reason)"
            case let .failed(reason):
                "failed — \(reason)"
            }
            return "\(item.unit?.title ?? item.target.title): \(status)"
        }.joined(separator: "\n")
    }
}
