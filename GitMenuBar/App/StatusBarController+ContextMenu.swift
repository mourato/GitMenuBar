import AppKit

@MainActor
extension StatusBarController {
    func rebuildContextMenu() {
        let menu = contextMenu ?? NSMenu()
        menu.removeAllItems()

        if appendCommandItems([.commit, .commitAndPush, .sync], to: menu) {
            menu.addItem(NSMenuItem.separator())
        }

        if appendCommandItems(
            [.openRepositoryOnGitHub, .revealRepositoryInFinder, .showRepositoryOptions],
            to: menu
        ) {
            menu.addItem(NSMenuItem.separator())
        }

        appendRecentProjectsMenu(to: menu)
        addCommandMenuItem(.chooseRepository, to: menu)
        menu.addItem(NSMenuItem.separator())

        addCommandMenuItem(.showSettings, to: menu)
        addCommandMenuItem(.quit, to: menu)

        contextMenu = menu
    }

    private func appendCommandItems(_ commandIDs: [AppCommandID], to menu: NSMenu) -> Bool {
        let hasEnabledItem = commandIDs.contains { appCommandCenter.state(for: $0).isEnabled }

        for commandID in commandIDs {
            addCommandMenuItem(commandID, to: menu)
        }

        return hasEnabledItem
    }

    private func addCommandMenuItem(_ commandID: AppCommandID, to menu: NSMenu) {
        let state = appCommandCenter.state(for: commandID)
        let item = makeMenuItem(
            title: state.title,
            action: #selector(handleContextMenuCommand(_:)),
            representedCommand: commandID,
            isEnabled: state.isEnabled
        )
        menu.addItem(item)
    }

    private func appendRecentProjectsMenu(to menu: NSMenu) {
        guard !appCommandCenter.recentProjects.isEmpty else {
            return
        }

        let recentMenuItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Open Recent")

        for project in appCommandCenter.recentProjects {
            let item = NSMenuItem(
                title: project.title,
                action: #selector(handleRecentProjectContextMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.toolTip = project.subtitle
            item.representedObject = project.path
            submenu.addItem(item)
        }

        recentMenuItem.submenu = submenu
        menu.addItem(recentMenuItem)
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        representedCommand: AppCommandID,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedCommand
        item.isEnabled = isEnabled
        return item
    }

    @objc private func handleContextMenuCommand(_ sender: NSMenuItem) {
        guard let commandID = sender.representedObject as? AppCommandID else {
            return
        }

        appCommandCenter.perform(commandID)
    }

    @objc private func handleRecentProjectContextMenuItem(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else {
            return
        }
        appCommandCenter.performRecentProject(path: path)
    }
}
