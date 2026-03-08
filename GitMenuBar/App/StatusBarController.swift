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
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var contextMenu: NSMenu?
    private var badgeRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var baseStatusImage: NSImage?

    let gitManager = GitManager()
    let loginItemManager = LoginItemManager()
    let githubAuthManager: GitHubAuthManager
    let aiProviderStore = AIProviderStore()
    let aiKeychainStore: any AIAPIKeyStore
    let aiCommitMessageService = AICommitMessageService()
    let shortcutActionBridge = MainMenuShortcutActionBridge()

    lazy var aiCommitCoordinator = AICommitCoordinator(
        providerStore: aiProviderStore,
        keychainStore: aiKeychainStore,
        messageService: aiCommitMessageService,
        gitManager: gitManager
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
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettingsFromContextMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromContextMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        contextMenu = menu
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = PopoverHostingController(rootView: makeRootView())
        self.popover = popover
    }

    private func makeRootView(
        initialScreen: MainMenuView.InitialScreen = .main,
        initialCreateRepoPath: String? = nil
    ) -> some View {
        MainMenuView(
            closePopover: { [weak self] in
                self?.popover?.close()
            },
            togglePopoverBehavior: { [weak self] in
                self?.togglePopoverBehavior()
            },
            initialScreen: initialScreen,
            initialCreateRepoPath: initialCreateRepoPath
        )
        .environmentObject(gitManager)
        .environmentObject(loginItemManager)
        .environmentObject(githubAuthManager)
        .environmentObject(aiProviderStore)
        .environmentObject(aiCommitCoordinator)
        .environmentObject(shortcutActionBridge)
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

        statusItem?.menu = contextMenu
        button.performClick(nil)
        statusItem?.menu = nil
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

        // Check if current repo path is set and is a git repo.
        let currentPath = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
        let isGitRepo = !currentPath.isEmpty && gitManager.isGitRepository(at: currentPath)

        if isGitRepo, githubAuthManager.isAuthenticated {
            // Check if remote exists on GitHub.
            gitManager.remoteRepositoryExists(at: currentPath) { [weak self] exists in
                guard let self else { return }

                if exists {
                    self.showMainView(initialScreen: .main)
                } else {
                    self.showCreateRepoView(path: currentPath)
                }
            }
        } else {
            showMainView(initialScreen: .main)
        }
    }

    private func showCreateRepoView(path: String) {
        presentPopover(initialCreateRepoPath: path)
    }

    private func showMainView(initialScreen: MainMenuView.InitialScreen) {
        gitManager.updateUncommittedFiles { [weak self] in
            guard let self else { return }
            self.presentPopover(initialScreen: initialScreen)
            self.gitManager.refresh()
        }
    }

    private func presentPopover(
        initialScreen: MainMenuView.InitialScreen = .main,
        initialCreateRepoPath: String? = nil
    ) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.close()
        }

        popover.contentViewController = nil
        let hostingController = PopoverHostingController(
            rootView: makeRootView(
                initialScreen: initialScreen,
                initialCreateRepoPath: initialCreateRepoPath
            )
        )
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 400, height: 500)

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func openSettingsPopover() {
        showMainView(initialScreen: .settings)
    }

    /// Opens the popover programmatically (used when app is launched with a folder path)
    func openPopover() {
        if popover?.isShown == true {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        showMainView(initialScreen: .main)
    }

    /// Opens the popover directly showing the create repo view (used when opening a non-git folder)
    func openPopoverWithCreateRepo(path: String) {
        presentPopover(initialCreateRepoPath: path)
    }
}

class PopoverHostingController<Content: View>: NSHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.window?.setContentSize(view.fittingSize)
    }
}
