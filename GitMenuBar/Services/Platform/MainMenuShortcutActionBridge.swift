import Combine
import Observation

enum MainMenuShortcutAction: Equatable {
    case commit
    case sync
    case atomicCommits
    case fetch
    case branchSelector
    case toolbarCommit
}

@MainActor
@Observable
final class MainMenuShortcutActionBridge {
    @ObservationIgnored let actions = PassthroughSubject<MainMenuShortcutAction, Never>()

    func send(_ action: MainMenuShortcutAction) {
        actions.send(action)
    }
}
