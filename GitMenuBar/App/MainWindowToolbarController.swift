import AppKit

@MainActor
final class MainWindowToolbarController: NSObject, NSToolbarDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("GitMenuBar.MainWindowToolbar")
    private static let backIdentifier = NSToolbarItem.Identifier("GitMenuBar.back")

    private weak var target: StatusBarController?
    private weak var window: NSWindow?
    private var toolbar: NSToolbar?

    init(target: StatusBarController) {
        self.target = target
        super.init()
    }

    func install(in window: NSWindow) {
        self.window = window

        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar
        self.toolbar = toolbar
    }

    func update(title: String, showsSidebarItem: Bool, showsBackItem: Bool) {
        window?.title = title

        var desiredItems: [NSToolbarItem.Identifier] = [.sidebarTrackingSeparator]
        if showsSidebarItem {
            desiredItems.insert(.toggleSidebar, at: 0)
        }
        if showsBackItem {
            desiredItems.append(Self.backIdentifier)
        }
        synchronizeItems(desiredItems)
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, .toggleSidebar, Self.backIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        makeItem(identifier: itemIdentifier)
    }

    private func makeItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        if identifier == .sidebarTrackingSeparator || identifier == .toggleSidebar {
            return NSToolbarItem(itemIdentifier: identifier)
        }

        guard identifier == Self.backIdentifier, let target else { return nil }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Back"
        item.paletteLabel = "Back"
        item.toolTip = "Return to the main repository view"
        item.action = #selector(StatusBarController.goBackFromToolbar(_:))
        item.target = target
        item.image = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back")
        return item
    }

    private func synchronizeItems(_ desiredItems: [NSToolbarItem.Identifier]) {
        guard let toolbar else { return }

        let desiredSet = Set(desiredItems)
        let removableIndexes = toolbar.items.enumerated()
            .filter { !desiredSet.contains($0.element.itemIdentifier) }
            .map(\.offset)
            .reversed()
        for index in removableIndexes {
            toolbar.removeItem(at: index)
        }

        for (index, identifier) in desiredItems.enumerated() {
            if let currentIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == identifier }) {
                guard currentIndex != index else { continue }
                toolbar.removeItem(at: currentIndex)
            }
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }
}
