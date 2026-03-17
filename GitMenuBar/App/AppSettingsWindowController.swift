import AppKit
import Settings

private extension Settings.PaneIdentifier {
    static let gitMenuBarGeneral = Self("gitmenubar.general")
    static let gitMenuBarAccounts = Self("gitmenubar.accounts")
    static let gitMenuBarShortcuts = Self("gitmenubar.shortcuts")
}

@MainActor
final class AppSettingsWindowController {
    private let windowController: SettingsWindowController

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
    }

    func show() {
        windowController.show(pane: .gitMenuBarGeneral)
        NSApp.activate(ignoringOtherApps: true)
        windowController.window?.makeKeyAndOrderFront(nil)
    }
}
