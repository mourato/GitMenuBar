import AppKit
import KeyboardShortcuts
import SwiftUI

enum AppCommandID: Hashable {
    case openWindow
    case showSettings
    case showCommandPalette
    case commit
    case commitAndPush
    case sync
    case chooseRepository
    case revealRepositoryInFinder
    case openRepositoryOnGitHub
    case showRepositoryOptions
    case helpRepository
    case reportIssue
    case quit

    var fallbackTitle: String {
        Self.fallbackTitles[self] ?? ""
    }

    private static let fallbackTitles: [AppCommandID: String] = [
        .openWindow: "Open Window",
        .showSettings: "Settings…",
        .showCommandPalette: "Command Palette",
        .commit: "Commit",
        .commitAndPush: "Commit & Push",
        .sync: "Sync Changes",
        .chooseRepository: "Choose Repository…",
        .revealRepositoryInFinder: "Reveal in Finder",
        .openRepositoryOnGitHub: "Open on GitHub",
        .showRepositoryOptions: "Repository Options…",
        .helpRepository: "GitMenuBar on GitHub",
        .reportIssue: "Report Issue",
        .quit: "Quit GitMenuBar"
    ]
}

struct AppCommandState: Equatable {
    let title: String
    let isEnabled: Bool
}

struct AppRecentProjectCommand: Equatable, Identifiable {
    let path: String
    let title: String
    let subtitle: String

    var id: String {
        path
    }
}

enum AppCommandInvocation: Equatable {
    case command(AppCommandID)
    case recentProject(path: String)
}

struct AppCommandSnapshot: Equatable {
    let states: [AppCommandID: AppCommandState]
    let recentProjects: [AppRecentProjectCommand]
}

struct AppCommandContext: Equatable {
    let actionState: StatusBarContextMenuActionState
    let syncActionTitle: String
    let currentRepoPath: String
    let remoteUrl: String
    let recentPaths: [String]
    let isGitHubAuthenticated: Bool
}

enum AppCommandResolver {
    static func resolveSnapshot(context: AppCommandContext) -> AppCommandSnapshot {
        let hasCurrentRepository = !context.currentRepoPath.isEmpty
        let canOpenRemoteRepository = GitHubRemoteURLParser.parse(context.remoteUrl) != nil
        let canShowRepositoryOptions = context.isGitHubAuthenticated && canOpenRemoteRepository

        let states: [AppCommandID: AppCommandState] = [
            .openWindow: .init(title: "Open Window", isEnabled: true),
            .showSettings: .init(title: "Settings…", isEnabled: true),
            .showCommandPalette: .init(title: "Command Palette", isEnabled: true),
            .commit: .init(title: "Commit", isEnabled: context.actionState.canCommit),
            .commitAndPush: .init(title: "Commit & Push", isEnabled: context.actionState.canCommitAndPush),
            .sync: .init(title: context.syncActionTitle, isEnabled: context.actionState.canSync),
            .chooseRepository: .init(title: "Choose Repository…", isEnabled: true),
            .revealRepositoryInFinder: .init(title: "Reveal in Finder", isEnabled: hasCurrentRepository),
            .openRepositoryOnGitHub: .init(title: "Open on GitHub", isEnabled: canOpenRemoteRepository),
            .showRepositoryOptions: .init(title: "Repository Options…", isEnabled: canShowRepositoryOptions),
            .helpRepository: .init(title: "GitMenuBar on GitHub", isEnabled: true),
            .reportIssue: .init(title: "Report Issue", isEnabled: true),
            .quit: .init(title: "Quit GitMenuBar", isEnabled: true)
        ]

        let recentProjects = context.recentPaths
            .filter { $0 != context.currentRepoPath }
            .prefix(5)
            .map {
                AppRecentProjectCommand(
                    path: $0,
                    title: PathDisplayFormatter.projectName(from: $0),
                    subtitle: PathDisplayFormatter.abbreviatedPath($0)
                )
            }

        return AppCommandSnapshot(states: states, recentProjects: Array(recentProjects))
    }
}

@MainActor
final class AppCommandCenter: ObservableObject {
    @Published private(set) var states: [AppCommandID: AppCommandState] = [:]
    @Published private(set) var recentProjects: [AppRecentProjectCommand] = []

    var performInvocation: ((AppCommandInvocation) -> Void)?

    func apply(_ snapshot: AppCommandSnapshot) {
        states = snapshot.states
        recentProjects = snapshot.recentProjects
    }

    func state(for commandID: AppCommandID) -> AppCommandState {
        states[commandID] ?? AppCommandState(title: commandID.fallbackTitle, isEnabled: false)
    }

    func perform(_ commandID: AppCommandID) {
        guard state(for: commandID).isEnabled else {
            NSSound.beep()
            return
        }

        performInvocation?(.command(commandID))
    }

    func performRecentProject(path: String) {
        performInvocation?(.recentProject(path: path))
    }
}

struct GitMenuBarCommandMenus: Commands {
    @ObservedObject var commandCenter: AppCommandCenter

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(commandCenter.state(for: .showSettings).title) {
                commandCenter.perform(.showSettings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Button(commandCenter.state(for: .showCommandPalette).title) {
                commandCenter.perform(.showCommandPalette)
            }
            .disabled(!commandCenter.state(for: .showCommandPalette).isEnabled)
        }

        CommandGroup(after: .windowArrangement) {
            Button(commandCenter.state(for: .openWindow).title) {
                commandCenter.perform(.openWindow)
            }
            .disabled(!commandCenter.state(for: .openWindow).isEnabled)
        }

        CommandMenu("Repository") {
            Button(commandCenter.state(for: .commit).title) {
                commandCenter.perform(.commit)
            }
            .disabled(!commandCenter.state(for: .commit).isEnabled)

            Button(commandCenter.state(for: .commitAndPush).title) {
                commandCenter.perform(.commitAndPush)
            }
            .disabled(!commandCenter.state(for: .commitAndPush).isEnabled)

            Button(commandCenter.state(for: .sync).title) {
                commandCenter.perform(.sync)
            }
            .disabled(!commandCenter.state(for: .sync).isEnabled)

            Divider()

            Button(commandCenter.state(for: .openRepositoryOnGitHub).title) {
                commandCenter.perform(.openRepositoryOnGitHub)
            }
            .disabled(!commandCenter.state(for: .openRepositoryOnGitHub).isEnabled)

            Button(commandCenter.state(for: .revealRepositoryInFinder).title) {
                commandCenter.perform(.revealRepositoryInFinder)
            }
            .disabled(!commandCenter.state(for: .revealRepositoryInFinder).isEnabled)

            Button(commandCenter.state(for: .showRepositoryOptions).title) {
                commandCenter.perform(.showRepositoryOptions)
            }
            .disabled(!commandCenter.state(for: .showRepositoryOptions).isEnabled)

            Divider()

            Menu("Open Recent") {
                if commandCenter.recentProjects.isEmpty {
                    Button("No Recent Repositories") {}
                        .disabled(true)
                } else {
                    ForEach(commandCenter.recentProjects) { project in
                        Button(project.title) {
                            commandCenter.performRecentProject(path: project.path)
                        }
                        .help(project.subtitle)
                    }
                }
            }

            Button(commandCenter.state(for: .chooseRepository).title) {
                commandCenter.perform(.chooseRepository)
            }
        }

        CommandGroup(after: .help) {
            Divider()

            Button(commandCenter.state(for: .helpRepository).title) {
                commandCenter.perform(.helpRepository)
            }

            Button(commandCenter.state(for: .reportIssue).title) {
                commandCenter.perform(.reportIssue)
            }
        }
    }
}
