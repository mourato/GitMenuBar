import AppKit
import Security
import SwiftUI

@main
struct GitMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            GitMenuBarCommandMenus()
            SidebarCommands()
        }
        .environment(appDelegate.appCommandCenter)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appCommandCenter = AppCommandCenter()
    var statusBarController: StatusBarController?

    @MainActor
    func showSettingsWindow() {
        statusBarController?.showSettingsWindow()
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !AppExecutionContext.isRunningTests else {
            return
        }

        let showDockIcon = MainWindowPreferences.isShowDockIconEnabled()
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)

        deleteLegacyGitHubToken()

        statusBarController = StatusBarController(
            appCommandCenter: appCommandCenter
        )

        statusBarController?.loginItemManager.checkLoginItemStatus()

        UpdateChecker.shared.checkForUpdatesOnLaunch()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        statusBarController?.openMainWindow()
        return true
    }

    func application(_: NSApplication, open urls: [URL]) {
        guard let folderUrl = urls.first else {
            return
        }

        let path = folderUrl.path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            print("GitMenuBar: Path is not a directory: \(path)")
            return
        }

        guard canSwitchRepository(to: path) else { return }

        guard case .selected = statusBarController?.repositorySelectionCoordinator.select(path: path) else { return }
        statusBarController?.actionCoordinator.resetForRepositorySwitch()
        Task { @MainActor in
            self.statusBarController?.openMainWindow()
        }
    }

    private func deleteLegacyGitHubToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.mourato.GitMenuBar",
            kSecAttrAccount as String: "github-access-token"
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func canSwitchRepository(to path: String) -> Bool {
        statusBarController?.actionCoordinator.canSwitchRepository(to: path) ?? true
    }
}
