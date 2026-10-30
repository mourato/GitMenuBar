enum MainWindowToolbarRepositoryItem: Equatable {
    case branchPicker
    case aheadBehind
    case fetch
    case sync
    case commit
}

struct MainWindowToolbarRepositoryState: Equatable {
    /// Repository actions belong only to the main route with a selected Git repository;
    /// a plain folder gets the create-repo banner instead.
    static func isAvailable(
        isMainRoute: Bool,
        repositoryPath: String?,
        isGitRepository: (String) -> Bool
    ) -> Bool {
        guard isMainRoute, let repositoryPath else { return false }
        return isGitRepository(repositoryPath)
    }

    let repositoryName: String
    let branchName: String
    let aheadCount: Int
    let behindCount: Int
    let changeCount: Int
    /// Files the next commit includes: staged files, or every change when
    /// nothing is staged. Matches the Working Tree commit button.
    let commitFileCount: Int
    let isBusy: Bool
    let busyItem: MainWindowToolbarRepositoryItem?
    let progressAccessibilityLabel: String?
    let isWorkingTreeOpen: Bool

    init(
        repositoryName: String,
        branchName: String,
        aheadCount: Int,
        behindCount: Int,
        changeCount: Int,
        commitFileCount: Int,
        isBusy: Bool,
        busyItem: MainWindowToolbarRepositoryItem?,
        progressAccessibilityLabel: String?,
        isWorkingTreeOpen: Bool = false
    ) {
        self.repositoryName = repositoryName
        self.branchName = branchName
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.changeCount = changeCount
        self.commitFileCount = commitFileCount
        self.isBusy = isBusy
        self.busyItem = busyItem
        self.progressAccessibilityLabel = progressAccessibilityLabel
        self.isWorkingTreeOpen = isWorkingTreeOpen
    }

    var repositoryItems: [MainWindowToolbarRepositoryItem] {
        var items: [MainWindowToolbarRepositoryItem] = [.branchPicker, .aheadBehind, .fetch]
        if showsSyncItem {
            items.append(.sync)
        }
        if showsCommitItem {
            items.append(.commit)
        }
        return items
    }

    var showsSyncItem: Bool {
        aheadCount > 0 || behindCount > 0 || busyItem == .sync
    }

    var showsCommitItem: Bool {
        guard !isWorkingTreeOpen else { return false }
        return changeCount > 0 || busyItem == .commit
    }

    var branchTitle: String {
        branchName.isEmpty ? "Branch" : branchName
    }

    var branchAccessibilityLabel: String {
        "Current branch \(branchTitle) in \(repositoryName)"
    }

    var aheadBehindTitle: String {
        var parts: [String] = []
        if aheadCount > 0 {
            parts.append("↑\(aheadCount)")
        }
        if behindCount > 0 {
            parts.append("↓\(behindCount)")
        }
        return parts.isEmpty ? "Up to date" : parts.joined(separator: " ")
    }

    var aheadBehindAccessibilityLabel: String {
        switch (aheadCount, behindCount) {
        case (0, 0):
            "\(repositoryName) is up to date"
        case let (ahead, 0):
            "\(repositoryName) is ahead by \(ahead) commit\(ahead == 1 ? "" : "s")"
        case let (0, behind):
            "\(repositoryName) is behind by \(behind) commit\(behind == 1 ? "" : "s")"
        case let (ahead, behind):
            "\(repositoryName) is ahead by \(ahead) and behind by \(behind) commits"
        }
    }

    var fetchAccessibilityLabel: String {
        "Fetch remote updates for \(repositoryName)"
    }

    var syncAccessibilityLabel: String {
        "Sync changes in \(repositoryName)"
    }

    var commitAccessibilityLabel: String {
        "Commit \(commitFileCount) file\(commitFileCount == 1 ? "" : "s") in \(repositoryName)"
    }

    var fetchTitle: String {
        "Fetch"
    }

    var syncTitle: String {
        "Sync"
    }

    var syncToolTip: String {
        changeCount > 0 ? "Commit changes before syncing" : syncAccessibilityLabel
    }

    var commitTitle: String {
        "Commit"
    }

    var commitItemTitle: String {
        commitFileCount > 0 ? "Commit (\(commitFileCount))" : commitTitle
    }

    var isSyncEnabled: Bool {
        !isBusy && changeCount == 0
    }

    var isFetchEnabled: Bool {
        !isBusy
    }

    var isCommitEnabled: Bool {
        !isBusy && changeCount > 0
    }
}
