import Foundation

@Observable
@MainActor
final class MainMenuSyncSheetState {
    var selectedPushBranch = ""
    var showPullToNewBranch = false
    var pullToNewBranchName = ""
    var useRebase = false
}
