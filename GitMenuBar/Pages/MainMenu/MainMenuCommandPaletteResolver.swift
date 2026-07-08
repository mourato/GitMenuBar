import Foundation

enum MainMenuCommandPaletteResolver {
    // swiftlint:disable:next function_parameter_count function_body_length
    static func resolveItems(
        actionState: StatusBarContextMenuActionState,
        syncActionTitle: String,
        recentPaths: [String],
        currentRepoPath: String,
        currentBranch: String,
        canDoAtomicCommits: Bool,
        isBehindRemote: Bool,
        isAheadOfRemote: Bool,
        canShowBranchManagement: Bool,
        defaultBranchName: String
    ) -> [MainMenuCommandPaletteItem] {
        var items: [MainMenuCommandPaletteItem] = []

        if actionState.showsCommit {
            items.append(item(commandID: .commit, kind: .commit, section: .actions, isEnabled: actionState.canCommit))
        }

        if actionState.showsCommitAndPush {
            items.append(item(
                commandID: .commitAndPush,
                kind: .commitAndPush,
                section: .actions,
                isEnabled: actionState.canCommitAndPush
            ))
        }

        if actionState.showsSync {
            items.append(item(
                commandID: .sync,
                kind: .sync,
                section: .actions,
                titleOverride: syncActionTitle,
                isEnabled: actionState.canSync
            ))
        }

        if canDoAtomicCommits {
            items.append(item(commandID: .atomicCommits, kind: .atomicCommits, section: .actions, isEnabled: true))
        }

        if isAheadOfRemote {
            items.append(item(commandID: .push, kind: .push, section: .actions, isEnabled: true))
        }

        if isBehindRemote {
            items.append(item(commandID: .pull, kind: .pull, section: .actions, isEnabled: true))
        }

        // Branch section
        items.append(item(
            commandID: .branchManagement,
            kind: .branchManagement,
            section: .branches,
            isEnabled: canShowBranchManagement
        ))

        items.append(item(
            commandID: .createBranch,
            kind: .createBranch,
            section: .branches,
            isEnabled: canShowBranchManagement
        ))

        let isOnDefaultBranch = currentBranch == defaultBranchName
        if !isOnDefaultBranch, !currentBranch.isEmpty, !defaultBranchName.isEmpty {
            items.append(
                item(
                    commandID: .mergeToDefault,
                    kind: .mergeToDefault(featureBranch: currentBranch),
                    section: .branches,
                    titleOverride: "Merge '\(currentBranch)' into \(defaultBranchName)",
                    isEnabled: true
                )
            )
        }

        items.append(
            MainMenuCommandPaletteItem(
                kind: .switchToBranchList,
                section: .branches,
                title: "Switch Branch\u{2026}",
                subtitle: "Check out a different branch",
                keywords: ["switch", "checkout", "branch"],
                isEnabled: canShowBranchManagement
            )
        )

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

        items.append(item(
            commandID: .quit,
            kind: .quitApp,
            section: .app,
            titleOverride: "Quit App",
            isEnabled: true
        ))

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

    private static func item(
        commandID: AppCommandID,
        kind: MainMenuCommandPaletteKind,
        section: MainMenuCommandPaletteSection,
        titleOverride: String? = nil,
        subtitleOverride: String? = nil,
        keywordsOverride: [String]? = nil,
        isEnabled: Bool
    ) -> MainMenuCommandPaletteItem {
        let descriptor = AppCommandCatalog.descriptor(for: commandID)
        return MainMenuCommandPaletteItem(
            kind: kind,
            section: section,
            title: titleOverride ?? descriptor.title,
            subtitle: subtitleOverride ?? descriptor.paletteSubtitle,
            keywords: keywordsOverride ?? descriptor.paletteKeywords,
            isEnabled: isEnabled
        )
    }
}
