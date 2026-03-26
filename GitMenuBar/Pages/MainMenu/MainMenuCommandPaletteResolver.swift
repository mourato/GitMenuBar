import Foundation

enum MainMenuCommandPaletteResolver {
    static func resolveItems(
        actionState: StatusBarContextMenuActionState,
        syncActionTitle: String,
        recentPaths: [String],
        currentRepoPath: String
    ) -> [MainMenuCommandPaletteItem] {
        var items: [MainMenuCommandPaletteItem] = []

        if actionState.showsCommit {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .commit,
                    section: .actions,
                    title: "Commit",
                    subtitle: "Generate an automatic commit message",
                    keywords: ["git", "commit", "working tree"],
                    isEnabled: actionState.canCommit
                )
            )
        }

        if actionState.showsCommitAndPush {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .commitAndPush,
                    section: .actions,
                    title: "Commit & Push",
                    subtitle: "Create a commit and push to remote",
                    keywords: ["git", "commit", "push", "remote"],
                    isEnabled: actionState.canCommitAndPush
                )
            )
        }

        if actionState.showsSync {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .sync,
                    section: .actions,
                    title: syncActionTitle,
                    subtitle: "Synchronize local and remote branches",
                    keywords: ["git", "sync", "pull", "push"],
                    isEnabled: actionState.canSync
                )
            )
        }

        for path in recentPaths.filter({ $0 != currentRepoPath }).prefix(5) {
            items.append(
                MainMenuCommandPaletteItem(
                    kind: .recentProject(path: path),
                    section: .recentProjects,
                    title: PathDisplayFormatter.projectName(from: path),
                    subtitle: PathDisplayFormatter.abbreviatedPath(path),
                    keywords: ["project", "switch", path],
                    isEnabled: true
                )
            )
        }

        items.append(
            MainMenuCommandPaletteItem(
                kind: .restartApp,
                section: .app,
                title: "Restart App",
                subtitle: "Relaunch GitMenuBar",
                keywords: ["restart", "relaunch", "app"],
                isEnabled: true
            )
        )

        items.append(
            MainMenuCommandPaletteItem(
                kind: .quitApp,
                section: .app,
                title: "Quit App",
                subtitle: "Close GitMenuBar",
                keywords: ["quit", "close", "app"],
                isEnabled: true
            )
        )

        return items
    }

    static func filteredItems(from items: [MainMenuCommandPaletteItem], query: String) -> [MainMenuCommandPaletteItem] {
        items.filter { $0.matches(query: query) }
    }

    static func defaultSelectionID(for items: [MainMenuCommandPaletteItem]) -> String? {
        if let firstEnabled = items.first(where: { $0.isEnabled }) {
            return firstEnabled.id
        }

        return items.first?.id
    }

    static func nextSelectionID(
        currentID: String?,
        items: [MainMenuCommandPaletteItem],
        direction: Int
    ) -> String? {
        guard !items.isEmpty else {
            return nil
        }

        guard let currentID,
              let currentIndex = items.firstIndex(where: { $0.id == currentID })
        else {
            return defaultSelectionID(for: items)
        }

        let normalizedDirection = direction >= 0 ? 1 : -1
        let nextIndex = (currentIndex + normalizedDirection + items.count) % items.count
        return items[nextIndex].id
    }

    static func executionDecision(for kind: MainMenuCommandPaletteKind) -> MainMenuCommandPaletteExecutionDecision {
        switch kind {
        case .restartApp:
            return .requiresConfirmation
        default:
            return .executeNow
        }
    }
}
