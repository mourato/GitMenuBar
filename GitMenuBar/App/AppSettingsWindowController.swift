import AppKit
import Combine
import Settings

private extension Settings.PaneIdentifier {
    static let gitMenuBarGeneral = Self("gitmenubar.general")
    static let gitMenuBarGit = Self("gitmenubar.git")
    static let gitMenuBarQuotas = Self("gitmenubar.quotas")
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
        usageQuotaStore: UsageQuotaStore,
        onSetAutoHideSuspended: @escaping (Bool) -> Void,
        onRequestCreateRepo: @escaping (String) -> Void
    ) {
        let generalPane = Settings.Pane(
            identifier: .gitMenuBarGeneral,
            title: "General",
            toolbarIcon: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General settings")
                ?? NSImage(named: NSImage.preferencesGeneralName)
                ?? NSImage(),
            contentView: {
                GeneralSettingsPaneView(loginItemManager: loginItemManager)
            }
        )
        let gitPane = Settings.Pane(
            identifier: .gitMenuBarGit,
            title: "Git",
            toolbarIcon: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Git settings")
                ?? NSImage(),
            contentView: {
                GitSettingsPaneView(
                    gitManager: gitManager,
                    githubAuthManager: githubAuthManager,
                    onSetAutoHideSuspended: onSetAutoHideSuspended,
                    onRequestCreateRepo: onRequestCreateRepo
                )
                .environmentObject(githubAuthManager)
                .environmentObject(aiProviderStore)
                .environmentObject(aiCommitCoordinator)
            }
        )
        let quotasPane = Settings.Pane(
            identifier: .gitMenuBarQuotas,
            title: "Quotas",
            toolbarIcon: NSImage(
                systemSymbolName: "gauge.with.dots.needle.33percent",
                accessibilityDescription: "Quotas settings"
            ) ?? NSImage(),
            contentView: {
                QuotasSettingsPaneView()
                    .environmentObject(usageQuotaStore)
            }
        )
        let shortcutsPane = Settings.Pane(
            identifier: .gitMenuBarShortcuts,
            title: "Shortcuts",
            toolbarIcon: NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Shortcuts settings")
                ?? NSImage(),
            contentView: {
                ShortcutsSettingsPaneView(
                    gitManager: gitManager,
                    githubAuthManager: githubAuthManager
                )
            }
        )

        windowController = SettingsWindowController(
            panes: [generalPane, gitPane, quotasPane, shortcutsPane],
            style: .toolbarItems,
            animated: false
        )

        configureWindowSizing()
        configureWindowShell()
        observeAppearancePreferenceChanges()
    }

    func show() {
        windowController.show(pane: .gitMenuBarGeneral)
        configureWindowShell()
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

    private func configureWindowShell() {
        guard let window = windowController.window else { return }
        WorkbenchWindowChrome.apply(to: window)
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
