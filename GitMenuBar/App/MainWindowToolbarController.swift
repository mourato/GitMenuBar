import AppKit

enum MainWindowToolbarRepositoryItem: Equatable {
    case branchPicker
    case aheadBehind
    case fetch
    case sync
    case commit
}

struct MainWindowToolbarRepositoryState: Equatable {
    let repositoryName: String
    let branchName: String
    let aheadCount: Int
    let behindCount: Int
    let changeCount: Int
    let isBusy: Bool
    let busyItem: MainWindowToolbarRepositoryItem?
    let progressAccessibilityLabel: String?

    var repositoryItems: [MainWindowToolbarRepositoryItem] {
        var items: [MainWindowToolbarRepositoryItem] = [.branchPicker, .aheadBehind, .fetch]
        if showsSyncItem {
            items.append(.sync)
        }
        if showsCommitItem {
            items.append(.commit)
        }
        return items
    }

    var showsSyncItem: Bool {
        aheadCount > 0 || behindCount > 0 || busyItem == .sync
    }

    var showsCommitItem: Bool {
        changeCount > 0 || busyItem == .commit
    }

    var branchTitle: String {
        branchName.isEmpty ? "Branch" : branchName
    }

    var branchAccessibilityLabel: String {
        "Current branch \(branchTitle) in \(repositoryName)"
    }

    var aheadBehindTitle: String {
        var parts: [String] = []
        if aheadCount > 0 {
            parts.append("↑\(aheadCount)")
        }
        if behindCount > 0 {
            parts.append("↓\(behindCount)")
        }
        return parts.isEmpty ? "Up to date" : parts.joined(separator: " ")
    }

    var aheadBehindAccessibilityLabel: String {
        switch (aheadCount, behindCount) {
        case (0, 0):
            "\(repositoryName) is up to date"
        case let (ahead, 0):
            "\(repositoryName) is ahead by \(ahead) commit\(ahead == 1 ? "" : "s")"
        case let (0, behind):
            "\(repositoryName) is behind by \(behind) commit\(behind == 1 ? "" : "s")"
        case let (ahead, behind):
            "\(repositoryName) is ahead by \(ahead) and behind by \(behind) commits"
        }
    }

    var fetchAccessibilityLabel: String {
        "Fetch remote updates for \(repositoryName)"
    }

    var syncAccessibilityLabel: String {
        "Sync changes in \(repositoryName)"
    }

    var commitAccessibilityLabel: String {
        "Commit \(changeCount) change\(changeCount == 1 ? "" : "s") in \(repositoryName)"
    }

    var isSyncEnabled: Bool {
        !isBusy && changeCount == 0
    }

    var isFetchEnabled: Bool {
        !isBusy
    }

    var isCommitEnabled: Bool {
        !isBusy && changeCount > 0
    }
}

@MainActor
final class MainWindowToolbarController: NSObject, NSToolbarDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("GitMenuBar.MainWindowToolbar")
    private static let backIdentifier = NSToolbarItem.Identifier("GitMenuBar.back")
    private static let branchPickerIdentifier = NSToolbarItem.Identifier("GitMenuBar.branchPicker")
    private static let aheadBehindIdentifier = NSToolbarItem.Identifier("GitMenuBar.aheadBehind")
    private static let fetchIdentifier = NSToolbarItem.Identifier("GitMenuBar.fetch")
    private static let syncIdentifier = NSToolbarItem.Identifier("GitMenuBar.sync")
    private static let commitIdentifier = NSToolbarItem.Identifier("GitMenuBar.commit")

    private weak var target: StatusBarController?
    private weak var window: NSWindow?
    private var toolbar: NSToolbar?
    private var repositoryState: MainWindowToolbarRepositoryState?

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
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar
        self.toolbar = toolbar
    }

    func update(
        title: String,
        showsSidebarItem: Bool,
        showsBackItem: Bool,
        repositoryState: MainWindowToolbarRepositoryState?
    ) {
        window?.title = title
        self.repositoryState = repositoryState

        var desiredItems: [NSToolbarItem.Identifier] = [.sidebarTrackingSeparator]
        if showsSidebarItem {
            desiredItems.insert(.toggleSidebar, at: 0)
        }
        if showsBackItem {
            desiredItems.append(Self.backIdentifier)
        }
        if let repositoryState {
            desiredItems.append(contentsOf: repositoryState.repositoryItems.map(Self.identifier(for:)))
        }
        synchronizeItems(desiredItems)
        applyRepositoryState()
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            .toggleSidebar,
            Self.backIdentifier,
            Self.branchPickerIdentifier,
            Self.aheadBehindIdentifier,
            Self.fetchIdentifier,
            Self.syncIdentifier,
            Self.commitIdentifier
        ]
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

        if let repositoryItem = repositoryItem(for: identifier), let repositoryState {
            let item = NSToolbarItem(itemIdentifier: identifier)
            configure(item, for: repositoryItem, state: repositoryState)
            return item
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

    private func applyRepositoryState() {
        guard let repositoryState else { return }

        for item in toolbar?.items ?? [] {
            guard let repositoryItem = repositoryItem(for: item.itemIdentifier) else { continue }
            configure(item, for: repositoryItem, state: repositoryState)
        }
    }

    private func configure(
        _ item: NSToolbarItem,
        for repositoryItem: MainWindowToolbarRepositoryItem,
        state: MainWindowToolbarRepositoryState
    ) {
        item.label = accessibilityLabel(for: repositoryItem, state: state)
        item.paletteLabel = item.label
        item.toolTip = item.label

        if state.isBusy, state.busyItem == repositoryItem {
            item.view = makeProgressView(accessibilityLabel: state.progressAccessibilityLabel ?? item.label)
            item.isEnabled = false
            return
        }

        guard let target else {
            item.view = nil
            item.isEnabled = false
            return
        }

        switch repositoryItem {
        case .branchPicker:
            let button = makeButton(
                title: state.branchTitle,
                imageName: "arrow.triangle.branch",
                accessibilityLabel: state.branchAccessibilityLabel,
                action: #selector(StatusBarController.presentBranchSelectorFromToolbar(_:)),
                target: target
            )
            item.view = button
            item.isEnabled = true
        case .aheadBehind:
            item.view = makeStatusView(
                title: state.aheadBehindTitle,
                accessibilityLabel: state.aheadBehindAccessibilityLabel
            )
            item.isEnabled = true
        case .fetch:
            let button = makeButton(
                title: "Fetch",
                imageName: "arrow.triangle.2.circlepath",
                accessibilityLabel: state.fetchAccessibilityLabel,
                action: #selector(StatusBarController.performFetchFromToolbar(_:)),
                target: target
            )
            button.isEnabled = state.isFetchEnabled
            item.view = button
            item.isEnabled = state.isFetchEnabled
        case .sync:
            let button = makeButton(
                title: "Sync",
                imageName: "arrow.2.circlepath",
                accessibilityLabel: state.syncAccessibilityLabel,
                action: #selector(StatusBarController.performSyncFromToolbar(_:)),
                target: target
            )
            button.isEnabled = state.isSyncEnabled
            item.view = button
            item.isEnabled = state.isSyncEnabled
        case .commit:
            let button = makeButton(
                title: "Commit \(state.changeCount)",
                imageName: "checkmark",
                accessibilityLabel: state.commitAccessibilityLabel,
                action: #selector(StatusBarController.selectWorkingTreeFromToolbar(_:)),
                target: target
            )
            button.isEnabled = state.isCommitEnabled
            item.view = button
            item.isEnabled = state.isCommitEnabled
        }
    }

    private func makeButton(
        title: String,
        imageName: String,
        accessibilityLabel: String,
        action: Selector,
        target: StatusBarController
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: accessibilityLabel)
        button.imagePosition = .imageLeading
        button.isBordered = false
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    private func makeStatusView(title: String, accessibilityLabel: String) -> NSTextField {
        let view = NSTextField(labelWithString: title)
        view.toolTip = accessibilityLabel
        view.setAccessibilityLabel(accessibilityLabel)
        return view
    }

    private func makeProgressView(accessibilityLabel: String) -> NSProgressIndicator {
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.setAccessibilityLabel(accessibilityLabel)
        progress.startAnimation(nil)
        return progress
    }

    private func accessibilityLabel(
        for item: MainWindowToolbarRepositoryItem,
        state: MainWindowToolbarRepositoryState
    ) -> String {
        switch item {
        case .branchPicker:
            state.branchAccessibilityLabel
        case .aheadBehind:
            state.aheadBehindAccessibilityLabel
        case .fetch:
            state.fetchAccessibilityLabel
        case .sync:
            state.syncAccessibilityLabel
        case .commit:
            state.commitAccessibilityLabel
        }
    }

    private static func identifier(for item: MainWindowToolbarRepositoryItem) -> NSToolbarItem.Identifier {
        switch item {
        case .branchPicker:
            branchPickerIdentifier
        case .aheadBehind:
            aheadBehindIdentifier
        case .fetch:
            fetchIdentifier
        case .sync:
            syncIdentifier
        case .commit:
            commitIdentifier
        }
    }

    private func repositoryItem(for identifier: NSToolbarItem.Identifier) -> MainWindowToolbarRepositoryItem? {
        switch identifier {
        case Self.branchPickerIdentifier:
            .branchPicker
        case Self.aheadBehindIdentifier:
            .aheadBehind
        case Self.fetchIdentifier:
            .fetch
        case Self.syncIdentifier:
            .sync
        case Self.commitIdentifier:
            .commit
        default:
            nil
        }
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
