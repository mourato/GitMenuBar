import Combine

enum MainMenuShortcutAction: Equatable {
    case commit
    case sync
}

@MainActor
final class MainMenuShortcutActionBridge: ObservableObject {
    let actions = PassthroughSubject<MainMenuShortcutAction, Never>()

    func send(_ action: MainMenuShortcutAction) {
        actions.send(action)
    }
}
