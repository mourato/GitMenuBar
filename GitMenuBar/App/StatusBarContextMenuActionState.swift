import Foundation

struct StatusBarContextMenuActionState: Equatable {
    let showsCommit: Bool
    let canCommit: Bool
    let showsCommitAndPush: Bool
    let canCommitAndPush: Bool
    let showsSync: Bool
    let canSync: Bool

    var hasVisibleActions: Bool {
        showsCommit || showsCommitAndPush || showsSync
    }

    static func resolve(
        hasCommitWork: Bool,
        hasSyncWork: Bool,
        canAutoCommit: Bool,
        canSync: Bool
    ) -> StatusBarContextMenuActionState {
        StatusBarContextMenuActionState(
            showsCommit: hasCommitWork,
            canCommit: hasCommitWork && canAutoCommit,
            showsCommitAndPush: hasCommitWork,
            canCommitAndPush: hasCommitWork && canAutoCommit,
            showsSync: hasSyncWork,
            canSync: hasSyncWork && canSync
        )
    }
}
