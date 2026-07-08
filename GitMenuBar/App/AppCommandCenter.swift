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
    case atomicCommits
    case branchManagement
    case push
    case pull
    case createBranch
    case mergeToDefault
    case chooseRepository
    case revealRepositoryInFinder
    case openRepositoryOnGitHub
    case showRepositoryOptions
    case helpRepository
    case reportIssue
    case quit

    var fallbackTitle: String {
        AppCommandCatalog.descriptor(for: self).title
    }
}

struct AppCommandDescriptor: Equatable {
    let title: String
    let paletteSubtitle: String?
    let paletteKeywords: [String]
}

enum AppCommandCatalog {
    static func descriptor(for commandID: AppCommandID) -> AppCommandDescriptor {
        descriptors[commandID] ?? AppCommandDescriptor(title: "", paletteSubtitle: nil, paletteKeywords: [])
    }

    private static let descriptors: [AppCommandID: AppCommandDescriptor] = [
        .openWindow: .init(title: "Open Window", paletteSubtitle: nil, paletteKeywords: ["window", "open"]),
        .showSettings: .init(title: "Settings…", paletteSubtitle: nil, paletteKeywords: ["settings", "preferences"]),
        .showCommandPalette: .init(title: "Command Palette", paletteSubtitle: nil, paletteKeywords: ["command", "palette"]),
        .commit: .init(
            title: "Commit",
            paletteSubtitle: "Generate an automatic commit message",
            paletteKeywords: ["git", "commit", "working tree"]
        ),
        .commitAndPush: .init(
            title: "Commit & Push",
            paletteSubtitle: "Create a commit and push to remote",
            paletteKeywords: ["git", "commit", "push", "remote"]
        ),
        .sync: .init(
            title: "Sync Changes",
            paletteSubtitle: "Synchronize local and remote branches",
            paletteKeywords: ["git", "sync", "pull", "push"]
        ),
        .atomicCommits: .init(
            title: "Create Atomic Commits",
            paletteSubtitle: "AI groups changes into logical commits",
            paletteKeywords: ["atomic", "commit", "ai", "group", "split"]
        ),
        .branchManagement: .init(
            title: "Manage Branches…",
            paletteSubtitle: "View, create, rename, delete branches",
            paletteKeywords: ["branch", "manage", "crud", "remote"]
        ),
        .push: .init(
            title: "Push Changes",
            paletteSubtitle: "Push local commits to remote",
            paletteKeywords: ["git", "push", "remote"]
        ),
        .pull: .init(
            title: "Pull Changes",
            paletteSubtitle: "Update from remote",
            paletteKeywords: ["git", "pull", "update", "remote"]
        ),
        .createBranch: .init(
            title: "Create Branch…",
            paletteSubtitle: "Create a new branch from current HEAD",
            paletteKeywords: ["branch", "create", "new"]
        ),
        .mergeToDefault: .init(
            title: "Merge to Default Branch",
            paletteSubtitle: "Merge current branch into default and clean up",
            paletteKeywords: ["merge", "default", "main", "master", "branch"]
        ),
        .chooseRepository: .init(title: "Choose Repository…", paletteSubtitle: nil, paletteKeywords: ["repository", "open"]),
        .revealRepositoryInFinder: .init(title: "Reveal in Finder", paletteSubtitle: nil, paletteKeywords: ["finder", "repository"]),
        .openRepositoryOnGitHub: .init(title: "Open on GitHub", paletteSubtitle: nil, paletteKeywords: ["github", "remote"]),
        .showRepositoryOptions: .init(title: "Repository Options…", paletteSubtitle: nil, paletteKeywords: ["repository", "options"]),
        .helpRepository: .init(title: "GitMenuBar on GitHub", paletteSubtitle: nil, paletteKeywords: ["help", "github"]),
        .reportIssue: .init(title: "Report Issue", paletteSubtitle: nil, paletteKeywords: ["issue", "bug"]),
        .quit: .init(
            title: "Quit GitMenuBar",
            paletteSubtitle: "Close GitMenuBar",
            paletteKeywords: ["quit", "close", "app"]
        )
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
    let hasWorkingTreeChanges: Bool
    let canDoAtomicCommits: Bool
    let isBehindRemote: Bool
    let isAheadOfRemote: Bool
    let canShowBranchManagement: Bool
    let currentBranch: String
    let defaultBranchName: String
}

enum AppCommandResolver {
    static func resolveSnapshot(context: AppCommandContext) -> AppCommandSnapshot {
        let hasCurrentRepository = !context.currentRepoPath.isEmpty
        let canOpenRemoteRepository = GitHubRemoteURLParser.parse(context.remoteUrl) != nil
        let canShowRepositoryOptions = context.isGitHubAuthenticated && canOpenRemoteRepository

        let isOnDefaultBranch = context.currentBranch == context.defaultBranchName
        let canMergeToDefault = hasCurrentRepository && !context.currentBranch.isEmpty
            && !context.defaultBranchName.isEmpty && !isOnDefaultBranch

        let states: [AppCommandID: AppCommandState] = [
            .openWindow: state(.openWindow, isEnabled: true),
            .showSettings: state(.showSettings, isEnabled: true),
            .showCommandPalette: state(.showCommandPalette, isEnabled: true),
            .commit: state(.commit, isEnabled: context.actionState.canCommit),
            .commitAndPush: state(.commitAndPush, isEnabled: context.actionState.canCommitAndPush),
            .sync: .init(title: context.syncActionTitle, isEnabled: context.actionState.canSync),
            .atomicCommits: state(.atomicCommits, isEnabled: context.canDoAtomicCommits),
            .branchManagement: state(.branchManagement, isEnabled: context.canShowBranchManagement),
            .push: state(.push, isEnabled: context.isAheadOfRemote),
            .pull: state(.pull, isEnabled: context.isBehindRemote),
            .createBranch: state(.createBranch, isEnabled: context.canShowBranchManagement),
            .mergeToDefault: state(.mergeToDefault, isEnabled: canMergeToDefault),
            .chooseRepository: state(.chooseRepository, isEnabled: true),
            .revealRepositoryInFinder: state(.revealRepositoryInFinder, isEnabled: hasCurrentRepository),
            .openRepositoryOnGitHub: state(.openRepositoryOnGitHub, isEnabled: canOpenRemoteRepository),
            .showRepositoryOptions: state(.showRepositoryOptions, isEnabled: canShowRepositoryOptions),
            .helpRepository: state(.helpRepository, isEnabled: true),
            .reportIssue: state(.reportIssue, isEnabled: true),
            .quit: state(.quit, isEnabled: true)
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

    private static func state(_ commandID: AppCommandID, isEnabled: Bool) -> AppCommandState {
        AppCommandState(
            title: AppCommandCatalog.descriptor(for: commandID).title,
            isEnabled: isEnabled
        )
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

        CommandGroup(replacing: .newItem) {
            Button(commandCenter.state(for: .chooseRepository).title) {
                commandCenter.perform(.chooseRepository)
            }
            .keyboardShortcut("o", modifiers: .command)

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
