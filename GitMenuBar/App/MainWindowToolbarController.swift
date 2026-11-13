import AppKit
import SwiftUI

@MainActor
final class MainWindowToolbarController: NSObject, NSToolbarDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier("GitMenuBar.MainWindowToolbar")
    private static let backIdentifier = NSToolbarItem.Identifier("GitMenuBar.back")
    private static let titleIdentifier = NSToolbarItem.Identifier("GitMenuBar.title")
    private static let branchPickerIdentifier = NSToolbarItem.Identifier("GitMenuBar.branchPicker")
    private static let aheadBehindIdentifier = NSToolbarItem.Identifier("GitMenuBar.aheadBehind")
    private static let fetchIdentifier = NSToolbarItem.Identifier("GitMenuBar.fetch")
    private static let syncIdentifier = NSToolbarItem.Identifier("GitMenuBar.sync")

    private weak var target: StatusBarController?
    private weak var window: NSWindow?
    private var toolbar: NSToolbar?
    private var repositoryState: MainWindowToolbarRepositoryState?
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        let base = NSFont.preferredFont(forTextStyle: .title3)
        label.font = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let branchSelectorContent: @MainActor () -> AnyView
    private let onBranchSelectorPopoverClosed: @MainActor () -> Void
    private var branchSelectorPopover: NSPopover?

    init(
        target: StatusBarController,
        branchSelectorContent: @escaping @MainActor () -> AnyView,
        onBranchSelectorPopoverClosed: @escaping @MainActor () -> Void
    ) {
        self.target = target
        self.branchSelectorContent = branchSelectorContent
        self.onBranchSelectorPopoverClosed = onBranchSelectorPopoverClosed
        super.init()
    }

    func install(in window: NSWindow) {
        self.window = window

        // The title is a toolbar item so branch context can sit right beside it;
        // the window title stays set for the Window menu and accessibility.
        window.titleVisibility = .hidden
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

    func setBranchSelectorPopoverPresented(_ isPresented: Bool) {
        if isPresented {
            presentBranchSelectorPopover()
        } else {
            branchSelectorPopover?.close()
        }
    }

    func update(
        title: String,
        showsSidebarItem: Bool,
        showsBackItem: Bool,
        repositoryState: MainWindowToolbarRepositoryState?
    ) {
        window?.title = title
        titleLabel.stringValue = title
        titleLabel.setAccessibilityLabel(title)
        self.repositoryState = repositoryState

        var desiredItems: [NSToolbarItem.Identifier] = [.sidebarTrackingSeparator]
        if showsSidebarItem {
            desiredItems.insert(.toggleSidebar, at: 0)
        }
        if showsBackItem {
            desiredItems.append(Self.backIdentifier)
        }
        desiredItems.append(Self.titleIdentifier)
        if let repositoryState {
            // Title, sync status, and branch chip stay together; actions sit on the trailing edge.
            let items = repositoryState.repositoryItems
            let leading: [MainWindowToolbarRepositoryItem] = [.aheadBehind, .branchPicker].filter(items.contains)
            let trailing = items.filter { !leading.contains($0) }
            desiredItems.append(contentsOf: leading.map(Self.identifier(for:)))
            desiredItems.append(.flexibleSpace)
            desiredItems.append(contentsOf: trailing.map(Self.identifier(for:)))
        }
        synchronizeItems(desiredItems)
        applyRepositoryState()
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            .toggleSidebar,
            .flexibleSpace,
            Self.titleIdentifier,
            Self.backIdentifier,
            Self.branchPickerIdentifier,
            Self.aheadBehindIdentifier,
            Self.fetchIdentifier,
            Self.syncIdentifier
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
        if identifier == .sidebarTrackingSeparator || identifier == .toggleSidebar || identifier == .flexibleSpace {
            return NSToolbarItem(itemIdentifier: identifier)
        }

        if identifier == Self.titleIdentifier {
            let item = NSToolbarItem(itemIdentifier: identifier)
            // Leading inset aligns the title with the content column below the toolbar.
            item.view = Self.inset(titleLabel, leading: WorkbenchMetrics.chipSpacing, trailing: WorkbenchMetrics.compactSpacing)
            // A plain label, not a control: keep it out of the toolbar's glass item background.
            item.isBordered = false
            return item
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
        item.image = Self.lucideImage(.chevronLeft, accessibilityDescription: "Back")
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
        let accessibilityLabel = accessibilityLabel(for: repositoryItem, state: state)
        let visibleLabel = visibleLabel(for: repositoryItem, state: state)
        item.label = visibleLabel
        item.paletteLabel = visibleLabel
        item.title = visibleLabel
        item.toolTip = toolTip(for: repositoryItem, state: state)
        item.image = image(for: repositoryItem, accessibilityLabel: accessibilityLabel)
        item.target = nil
        item.action = nil
        item.view = nil
        item.isBordered = false

        if state.isBusy, state.busyItem == repositoryItem {
            item.toolTip = state.progressAccessibilityLabel ?? item.toolTip
            item.view = makeProgressView(accessibilityLabel: state.progressAccessibilityLabel ?? accessibilityLabel)
            item.isEnabled = false
            return
        }

        guard let target else {
            item.isEnabled = false
            return
        }

        switch repositoryItem {
        case .branchPicker:
            item.view = makeBranchChip(
                title: state.branchTitle,
                accessibilityLabel: accessibilityLabel,
                target: target
            )
            item.isEnabled = true
        case .aheadBehind:
            item.view = makeStatusView(
                title: state.aheadBehindTitle,
                accessibilityLabel: accessibilityLabel
            )
            item.isEnabled = true
        case .fetch:
            configureStandardItem(
                item,
                action: #selector(StatusBarController.performFetchFromToolbar(_:)),
                target: target,
                isEnabled: state.isFetchEnabled
            )
        case .sync:
            configureStandardItem(
                item,
                action: #selector(StatusBarController.performSyncFromToolbar(_:)),
                target: target,
                isEnabled: state.isSyncEnabled
            )
        }
    }

    private func configureStandardItem(
        _ item: NSToolbarItem,
        action: Selector,
        target: StatusBarController,
        isEnabled: Bool
    ) {
        item.target = target
        item.action = action
        item.isBordered = true
        item.isEnabled = isEnabled
    }

    private func makeBranchChip(
        title: String,
        accessibilityLabel: String,
        target: StatusBarController
    ) -> NSButton {
        let chip = NSButton(
            title: title,
            target: target,
            action: #selector(StatusBarController.presentBranchSelectorFromToolbar(_:))
        )
        chip.bezelStyle = .accessoryBarAction
        chip.controlSize = .small
        chip.image = NSImage(lucide: .gitBranch)
        chip.imagePosition = .imageLeading
        chip.toolTip = accessibilityLabel
        chip.setAccessibilityLabel(accessibilityLabel)
        return chip
    }

    private func makeStatusView(title: String, accessibilityLabel: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabelColor
        label.toolTip = accessibilityLabel
        label.setAccessibilityLabel(accessibilityLabel)
        return Self.inset(label, leading: 0, trailing: WorkbenchMetrics.compactSpacing)
    }

    /// Wraps a toolbar view with horizontal insets; toolbar items add no spacing around custom views.
    private static func inset(_ view: NSView, leading: CGFloat, trailing: CGFloat) -> NSView {
        let stack = NSStackView(views: [view])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: leading, bottom: 0, right: trailing)
        return stack
    }

    private func presentBranchSelectorPopover() {
        guard let branchPickerItem = toolbar?.items.first(where: {
            $0.itemIdentifier == Self.branchPickerIdentifier
        }) else {
            return
        }

        let popover = branchSelectorPopover ?? makeBranchSelectorPopover()
        popover.contentViewController = NSHostingController(rootView: branchSelectorContent())
        popover.show(relativeTo: branchPickerItem)
    }

    private func makeBranchSelectorPopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        branchSelectorPopover = popover
        return popover
    }

    private func visibleLabel(
        for item: MainWindowToolbarRepositoryItem,
        state: MainWindowToolbarRepositoryState
    ) -> String {
        switch item {
        case .branchPicker:
            state.branchTitle
        case .aheadBehind:
            state.aheadBehindTitle
        case .fetch:
            state.fetchTitle
        case .sync:
            state.syncTitle
        }
    }

    private func toolTip(
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
            state.syncToolTip
        }
    }

    private func image(
        for item: MainWindowToolbarRepositoryItem,
        accessibilityLabel: String
    ) -> NSImage? {
        let name: LucideIconName? = switch item {
        case .branchPicker:
            .chevronDown
        case .aheadBehind:
            nil
        case .fetch:
            .circleArrowDown
        case .sync:
            .refreshCw
        }
        guard let name else { return nil }
        return Self.lucideImage(name, accessibilityDescription: accessibilityLabel)
    }

    /// Catalog image for a toolbar item, keeping the VoiceOver description
    /// the SF Symbol initializer used to take as a parameter.
    private static func lucideImage(
        _ name: LucideIconName,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let image = NSImage(lucide: name) else { return nil }
        image.accessibilityDescription = accessibilityDescription
        return image
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

extension MainWindowToolbarController: NSPopoverDelegate {
    func popoverDidClose(_: Notification) {
        onBranchSelectorPopoverClosed()
    }
}
