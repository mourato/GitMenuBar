import AppKit

@MainActor
extension StatusBarController {
    func rebuildContextMenu() {
        let menu = contextMenu ?? NSMenu()
        menu.removeAllItems()

        if let usageQuotaMenuItem = makeUsageQuotaMenuItem() {
            menu.addItem(usageQuotaMenuItem)
            menu.addItem(NSMenuItem.separator())
        }

        addCommandMenuItem(.showSettings, to: menu)
        addCommandMenuItem(.quit, to: menu)

        contextMenu = menu
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
}
