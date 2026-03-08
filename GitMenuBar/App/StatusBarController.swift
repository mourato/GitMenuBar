//
//  StatusBarController.swift
//  GitMenuBar
//

import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
class StatusBarController: ObservableObject {
    private struct PopoverOpenTrace {
        let id: Int
        let startedAt: CFAbsoluteTime
        let trigger: String
    }

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hostingController: PopoverHostingController<AnyView>?
    private var contextMenu: NSMenu?
    private var badgeRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var baseStatusImage: NSImage?
    private var remoteExistenceByPath: [String: RemoteExistenceState] = [:]
    private var nextPopoverOpenTraceID = 0
    let gitManager = GitManager()
    let loginItemManager = LoginItemManager()
    let githubAuthManager: GitHubAuthManager
    let aiProviderStore = AIProviderStore()
    let aiKeychainStore: any AIAPIKeyStore
    let aiCommitMessageService = AICommitMessageService()
    let shortcutActionBridge = MainMenuShortcutActionBridge()
    let presentationModel = MainMenuPresentationModel()

    lazy var aiCommitCoordinator = AICommitCoordinator(
        providerStore: aiProviderStore,
        keychainStore: aiKeychainStore,
        messageService: aiCommitMessageService,
        gitManager: gitManager
    )
    lazy var actionCoordinator = MainMenuActionCoordinator(
        gitManager: gitManager,
        aiCommitCoordinator: aiCommitCoordinator
    )

    init(githubAuthManager: GitHubAuthManager) {
        self.githubAuthManager = githubAuthManager
        if AppExecutionContext.usesEphemeralCredentialStores {
            aiKeychainStore = InMemoryAIAPIKeyStore()
        } else {
            let cachedStore = CachedAIAPIKeyStore(backingStore: AIKeychainStore())
            cachedStore.preloadAllKeys() // Eagerly load all keys to avoid multiple keychain prompts
            aiKeychainStore = cachedStore
        }

        // Wire up token provider for git push operations
        gitManager.tokenProvider = { [weak githubAuthManager] in
            githubAuthManager?.getStoredToken()
        }

        // Wire up GitHub API client for checking repo existence
        gitManager.githubAPIClient = GitHubAPIClient(authManager: githubAuthManager)

        setupStatusItem()
        setupContextMenu()
        setupPopover()
        setupBadgeObservation()
        setupBadgeRefreshTimer()
        setupShortcutHandlers()

        gitManager.updateUncommittedFiles()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 20)
        baseStatusImage = makeBaseStatusImage()

        guard let button = statusItem?.button else { return }
        button.image = baseStatusImage
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self

        updateStatusItemBadge(count: 0)
    }

    private func makeBaseStatusImage() -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            let resized = image.copy() as? NSImage ?? image
            resized.size = NSSize(width: 18, height: 18)
            resized.isTemplate = true
            return resized
        }

        let fallback = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: "GitBar")
        fallback?.isTemplate = true
        return fallback
    }

    private func updateStatusItemBadge(count: Int) {
        guard let button = statusItem?.button else { return }

        guard count > 0 else {
            button.image = baseStatusImage
            return
        }

        button.image = makeBadgedImage(count: count)
    }

    private func makeBadgedImage(count: Int) -> NSImage? {
        guard let baseStatusImage else { return nil }

        let iconSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: iconSize)

        image.lockFocus()

        let iconRect = NSRect(x: 0, y: 0, width: iconSize.width, height: iconSize.height)
        baseStatusImage.draw(in: iconRect)

        let displayText = count > 99 ? "99+" : "\(count)"
        let badgeWidth: CGFloat = displayText.count >= 3 ? 17 : (displayText.count == 2 ? 14 : 12)
        let badgeRect = NSRect(x: iconSize.width - badgeWidth + 1, y: iconSize.height - 11, width: badgeWidth, height: 11)

        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5.5, yRadius: 5.5).fill()

        let fontSize: CGFloat = displayText.count >= 3 ? 6 : 8
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = displayText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: badgeRect.midX - (textSize.width / 2),
            y: badgeRect.midY - (textSize.height / 2),
            width: textSize.width,
            height: textSize.height
        )

        displayText.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func setupBadgeObservation() {
        gitManager.$uncommittedFiles
            .receive(on: RunLoop.main)
            .sink { [weak self] files in
                self?.updateStatusItemBadge(count: files.count)
            }
            .store(in: &cancellables)
    }

    private func setupBadgeRefreshTimer() {
        badgeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.gitManager.updateUncommittedFiles()
        }

        if let badgeRefreshTimer {
            RunLoop.main.add(badgeRefreshTimer, forMode: .common)
        }
    }

    private func setupShortcutHandlers() {
        KeyboardShortcuts.onKeyDown(for: .togglePopover) { [weak self] in
            Task { @MainActor in
                self?.togglePopover(nil)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .commit) { [weak self] in
            Task { @MainActor in
                self?.dispatchShortcutAction(.commit)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .sync) { [weak self] in
            Task { @MainActor in
                self?.dispatchShortcutAction(.sync)
            }
        }
    }

    private func dispatchShortcutAction(_ action: MainMenuShortcutAction) {
        guard popover?.isShown == true else { return }
        shortcutActionBridge.send(action)
    }

    private func setupContextMenu() {
        contextMenu = NSMenu()
        rebuildContextMenu()
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        let hostingController = PopoverHostingController(rootView: makeRootView())
        popover.contentViewController = hostingController
        self.hostingController = hostingController
        self.popover = popover
    }

    private func makeRootView() -> AnyView {
        let rootView = MainMenuView(
            closePopover: { [weak self] in
                self?.popover?.close()
            },
            togglePopoverBehavior: { [weak self] in
                self?.togglePopoverBehavior()
            }
        )
        .environmentObject(gitManager)
        .environmentObject(loginItemManager)
        .environmentObject(githubAuthManager)
        .environmentObject(aiProviderStore)
        .environmentObject(aiCommitCoordinator)
        .environmentObject(actionCoordinator)
        .environmentObject(shortcutActionBridge)
        .environmentObject(presentationModel)

        return AnyView(rootView)
    }

    func togglePopoverBehavior() {
        if popover?.behavior == .transient {
            popover?.behavior = .applicationDefined
        } else {
            popover?.behavior = .transient
        }
    }

    @objc private func handleStatusItemClick(_: AnyObject?) {
        guard let currentEvent = NSApp.currentEvent else {
            togglePopover(nil)
            return
        }

        switch currentEvent.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseUp where currentEvent.modifierFlags.contains(.control):
            showContextMenu()
        default:
            togglePopover(nil)
        }
    }

    private func showContextMenu() {
        guard let contextMenu, let button = statusItem?.button else { return }

        rebuildContextMenu()
        statusItem?.menu = contextMenu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func rebuildContextMenu() {
        let menu = contextMenu ?? NSMenu()
        menu.removeAllItems()

        let actionState = StatusBarContextMenuActionState.resolve(
            hasCommitWork: actionCoordinator.hasWorkingTreeChanges,
            hasSyncWork: actionCoordinator.hasSyncWork,
            canAutoCommit: actionCoordinator.canAutoCommit,
            canSync: actionCoordinator.canSync
        )

        if actionState.showsCommit {
            let commitItem = NSMenuItem(title: "Commit", action: #selector(commitFromContextMenu), keyEquivalent: "")
            commitItem.target = self
            commitItem.isEnabled = actionState.canCommit
            menu.addItem(commitItem)
        }

        if actionState.showsCommitAndPush {
            let commitAndPushItem = NSMenuItem(
                title: "Commit & Push",
                action: #selector(commitAndPushFromContextMenu),
                keyEquivalent: ""
            )
            commitAndPushItem.target = self
            commitAndPushItem.isEnabled = actionState.canCommitAndPush
            menu.addItem(commitAndPushItem)
        }

        if actionState.showsSync {
            let syncItem = NSMenuItem(
                title: "Sync Changes",
                action: #selector(syncFromContextMenu),
                keyEquivalent: ""
            )
            syncItem.target = self
            syncItem.isEnabled = actionState.canSync
            menu.addItem(syncItem)
        }

        if actionState.hasVisibleActions {
            menu.addItem(NSMenuItem.separator())
        }

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettingsFromContextMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromContextMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        contextMenu = menu
    }

    @objc private func commitFromContextMenu() {
        Task { @MainActor in
            let result = await actionCoordinator.performCommit(
                commentText: "",
                forceAutomaticMessage: true
            )
            if result.shouldOpenPopover {
                presentMainPopoverForActionFeedback()
            }
        }
    }

    @objc private func commitAndPushFromContextMenu() {
        Task { @MainActor in
            let result = await actionCoordinator.performCommit(
                commentText: "",
                forceAutomaticMessage: true,
                shouldPushAfterCommit: true
            )
            if result.shouldOpenPopover {
                presentMainPopoverForActionFeedback()
            }
        }
    }

    @objc private func syncFromContextMenu() {
        Task { @MainActor in
            let result = await actionCoordinator.performSync()
            if result.shouldOpenPopover {
                presentMainPopoverForActionFeedback()
            }
        }
    }

    @objc private func openSettingsFromContextMenu() {
        openSettingsPopover()
    }

    @objc private func quitFromContextMenu() {
        NSApplication.shared.terminate(nil)
    }

    @objc func togglePopover(_: AnyObject?) {
        if popover?.isShown == true {
            popover?.close()
            return
        }

        let trace = beginPopoverOpenTrace(trigger: "toggle")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false
        let initialRoute = initialRoute(for: repositoryPath, isGitRepo: isGitRepo)

        openPopover(
            route: initialRoute,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: shouldRefreshAfterPresenting(route: initialRoute),
            trace: trace
        )
    }

    private func openPopover(
        route: MainMenuRoute,
        repositoryPath: String?,
        isGitRepo: Bool,
        shouldRefreshAfterPresentation: Bool,
        trace: PopoverOpenTrace
    ) {
        presentationModel.prepareForPresentation(route: route, requestCommitFocus: route == .main)
        if route != .main {
            presentationModel.clearCreateRepoSuggestion()
        }

        logPopoverOpen(trace, message: "route resolved to \(describe(route: route))")
        presentPopover(trace: trace)

        if shouldRefreshAfterPresentation {
            refreshPopoverData(trace: trace)
        } else {
            presentationModel.finishRefresh()
        }

        validateRemoteIfNeeded(path: repositoryPath, isGitRepo: isGitRepo, trace: trace)
    }

    private func presentPopover(trace: PopoverOpenTrace) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.close()
        }

        popover.contentSize = NSSize(width: 400, height: 700)

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        logPopoverOpen(trace, message: "popover shown")
    }

    private func openSettingsPopover() {
        let trace = beginPopoverOpenTrace(trigger: "settings")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false

        openPopover(
            route: .settings,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: true,
            trace: trace
        )
    }

    /// Opens the popover programmatically (used when app is launched with a folder path)
    func openPopover() {
        if popover?.isShown == true {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let trace = beginPopoverOpenTrace(trigger: "programmatic")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false
        let initialRoute = initialRoute(for: repositoryPath, isGitRepo: isGitRepo)

        openPopover(
            route: initialRoute,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: shouldRefreshAfterPresenting(route: initialRoute),
            trace: trace
        )
    }

    private func presentMainPopoverForActionFeedback() {
        if popover?.isShown == true {
            presentationModel.showMain(requestCommitFocus: true)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let trace = beginPopoverOpenTrace(trigger: "context_action")
        let repositoryPath = currentRepositoryPath()
        let isGitRepo = repositoryPath.map { gitManager.isGitRepository(at: $0) } ?? false

        openPopover(
            route: .main,
            repositoryPath: repositoryPath,
            isGitRepo: isGitRepo,
            shouldRefreshAfterPresentation: true,
            trace: trace
        )
    }

    /// Opens the popover directly showing the create repo view (used when opening a non-git folder)
    func openPopoverWithCreateRepo(path: String) {
        let trace = beginPopoverOpenTrace(trigger: "create_repo")
        openPopover(
            route: .createRepo(path: path),
            repositoryPath: path,
            isGitRepo: gitManager.isGitRepository(at: path),
            shouldRefreshAfterPresentation: false,
            trace: trace
        )
    }

    private func currentRepositoryPath() -> String? {
        let path = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
        return path.isEmpty ? nil : path
    }

    private func initialRoute(for repositoryPath: String?, isGitRepo: Bool) -> MainMenuRoute {
        guard let repositoryPath, isGitRepo, githubAuthManager.isAuthenticated else {
            return .main
        }

        switch remoteExistenceByPath[repositoryPath] ?? .unknown {
        case .missing:
            return .createRepo(path: repositoryPath)
        case .unknown, .checking, .exists:
            return .main
        }
    }

    private func shouldRefreshAfterPresenting(route: MainMenuRoute) -> Bool {
        if case .createRepo = route {
            return false
        }

        return true
    }

    private func refreshPopoverData(trace: PopoverOpenTrace) {
        presentationModel.startRefresh()
        logPopoverOpen(trace, message: "refresh started")

        gitManager.updateUncommittedFiles { [weak self] in
            guard let self else { return }

            self.logPopoverOpen(trace, message: "working tree loaded")
            self.gitManager.refresh {
                self.presentationModel.finishRefresh()
                self.logPopoverOpen(trace, message: "refresh completed")
            }
        }
    }

    private func validateRemoteIfNeeded(path: String?, isGitRepo: Bool, trace: PopoverOpenTrace) {
        guard let path, isGitRepo, githubAuthManager.isAuthenticated else {
            presentationModel.clearCreateRepoSuggestion()
            return
        }

        let cachedState = remoteExistenceByPath[path] ?? .unknown
        guard cachedState == .unknown else {
            if cachedState == .exists {
                presentationModel.clearCreateRepoSuggestion()
            } else if cachedState == .missing, presentationModel.route == .main {
                presentationModel.suggestCreateRepo(path: path)
            }
            return
        }

        remoteExistenceByPath[path] = .checking
        logPopoverOpen(trace, message: "remote validation started")

        gitManager.remoteRepositoryExists(at: path) { [weak self] exists in
            guard let self else { return }

            self.remoteExistenceByPath[path] = exists ? .exists : .missing
            self.logPopoverOpen(trace, message: "remote validation completed (\(exists ? "exists" : "missing"))")

            guard self.currentRepositoryPath() == path else { return }

            if exists {
                self.presentationModel.clearCreateRepoSuggestion()
                return
            }

            if self.presentationModel.route == .main {
                self.presentationModel.suggestCreateRepo(path: path)
            }
        }
    }

    private func beginPopoverOpenTrace(trigger: String) -> PopoverOpenTrace {
        nextPopoverOpenTraceID += 1
        let trace = PopoverOpenTrace(
            id: nextPopoverOpenTraceID,
            startedAt: CFAbsoluteTimeGetCurrent(),
            trigger: trigger
        )

        print("[PopoverOpen #\(trace.id)] trigger=\(trigger) +0ms")
        return trace
    }

    private func logPopoverOpen(_ trace: PopoverOpenTrace, message: String) {
        let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - trace.startedAt) * 1000)
        print("[PopoverOpen #\(trace.id)] trigger=\(trace.trigger) +\(elapsedMilliseconds)ms \(message)")
    }

    private func describe(route: MainMenuRoute) -> String {
        switch route {
        case .main:
            return "main"
        case .settings:
            return "settings"
        case .history:
            return "history"
        case let .createRepo(path):
            return "createRepo(\(path))"
        }
    }
}

class PopoverHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.window?.setContentSize(view.fittingSize)
    }
}
