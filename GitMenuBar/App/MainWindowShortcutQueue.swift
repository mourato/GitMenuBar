import Foundation

struct MainWindowShortcutQueue {
    private(set) var pendingActions: [MainMenuShortcutAction] = []

    mutating func enqueue(_ action: MainMenuShortcutAction) {
        pendingActions.append(action)
    }

    mutating func dequeueAllIfReady(isWindowVisible: Bool, isMainRoute: Bool) -> [MainMenuShortcutAction] {
        guard isWindowVisible, isMainRoute, !pendingActions.isEmpty else {
            return []
        }

        let actions = pendingActions
        pendingActions.removeAll(keepingCapacity: true)
        return actions
    }
}
