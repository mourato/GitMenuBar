import AppKit
import Combine
import Settings

private extension Settings.PaneIdentifier {
    static let gitMenuBarGeneral = Self("gitmenubar.general")
    static let gitMenuBarAccounts = Self("gitmenubar.accounts")
    static let gitMenuBarShortcuts = Self("gitmenubar.shortcuts")
}

@MainActor
final class AppSettingsWindowController {
    private enum Constants {
        static let minimumContentSize = NSSize(width: 420, height: 700)
    }

    private let windowController: SettingsWindowController
    private var cancellables = Set<AnyCancellable>()

    init(
        gitManager: GitManager,
        loginItemManager: LoginItemManager,
        githubAuthManager: GitHubAuthManager,
        aiProviderStore: AIProviderStore,
        aiCommitCoordinator: AICommitCoordinator,
        onSetAutoHideSuspended: @escaping (Bool) -> Void,
        onRequestCreateRepo: @escaping (String) -> Void
    ) {
        let toolbarIcon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General settings")
            ?? NSImage(named: NSImage.preferencesGeneralName)
            ?? NSImage()

        let generalPane = Settings.Pane(
            identifier: .gitMenuBarGeneral,
            title: "General",
            toolbarIcon: toolbarIcon,
            contentView: {
                GeneralSettingsPaneView(
                    gitManager: gitManager,
                    loginItemManager: loginItemManager,
                    githubAuthManager: githubAuthManager,
                    onSetAutoHideSuspended: onSetAutoHideSuspended,
                    onRequestCreateRepo: onRequestCreateRepo
                )
            }
        )
        let accountsPane = Settings.Pane(
            identifier: .gitMenuBarAccounts,
            title: "Accounts",
            toolbarIcon: NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Accounts settings") ?? NSImage(),
            contentView: {
                AccountsSettingsPaneView(onSetAutoHideSuspended: onSetAutoHideSuspended)
                    .environmentObject(githubAuthManager)
                    .environmentObject(aiProviderStore)
                    .environmentObject(aiCommitCoordinator)
            }
        )
        let shortcutsPane = Settings.Pane(
            identifier: .gitMenuBarShortcuts,
            title: "Shortcuts",
            toolbarIcon: NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Shortcuts settings") ?? NSImage(),
            contentView: {
                ShortcutsSettingsPaneView(
                    gitManager: gitManager,
                    githubAuthManager: githubAuthManager
                )
            }
        )

        windowController = SettingsWindowController(
            panes: [generalPane, accountsPane, shortcutsPane],
            style: .toolbarItems,
            animated: false
        )

        configureWindowSizing()
        observeAppearancePreferenceChanges()
    }

    func show() {
        windowController.show(pane: .gitMenuBarGeneral)
        applyConfiguredAppearance()
        NSApp.activate(ignoringOtherApps: true)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    private func observeAppearancePreferenceChanges() {
        NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.applyConfiguredAppearance()
        }
        .store(in: &cancellables)
    }

    private func applyConfiguredAppearance() {
        let appearanceRawValue = UserDefaults.standard.string(forKey: AppPreferences.Keys.appearanceMode)
            ?? AppPreferences.AppearanceMode.defaultMode.rawValue
        let appearanceMode = AppPreferences.AppearanceMode.resolve(rawValue: appearanceRawValue)
        windowController.window?.appearance = appearanceMode.nsAppearance
    }

    private func configureWindowSizing() {
        guard let window = windowController.window else { return }

        window.styleMask.insert(.resizable)
        window.contentMinSize = Constants.minimumContentSize
    }
}

private extension AppPreferences.AppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .systemDefault:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}
