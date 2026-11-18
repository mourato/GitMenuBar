//
//  GitMenuBarApp.swift
//  GitMenuBar
//

import AppKit
import Security
import SwiftUI

@main
struct GitMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Remove default WindowGroup since we're a menu bar app
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

        // Configure activation policy based on preferences
        let showDockIcon = MainWindowPreferences.isShowDockIconEnabled()
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)

        deleteLegacyGitHubToken()

        // Create and show status bar controller - keep strong reference
        statusBarController = StatusBarController(
            appCommandCenter: appCommandCenter
        )

        // Check login item status after controller is created
        statusBarController?.loginItemManager.checkLoginItemStatus()

        // Check for updates on launch
        UpdateChecker.shared.checkForUpdatesOnLaunch()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // Reopen the app if clicked while hidden
        NSApp.activate(ignoringOtherApps: true)
        statusBarController?.openMainWindow()
        return true
    }

    // MARK: - Handle file/folder URLs opened via "open -a GitMenuBar /path/to/folder"

    func application(_: NSApplication, open urls: [URL]) {
        // Handle folder paths passed via "open -a GitMenuBar /path/to/folder"
        guard let folderUrl = urls.first else {
            return
        }

        let path = folderUrl.path

        // Verify the path exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            print("GitMenuBar: Path is not a directory: \(path)")
            return
        }

        // Only git repositories can be selected.
        guard canSwitchRepository(to: path) else { return }

        guard case .selected = statusBarController?.repositorySelectionCoordinator.select(path: path) else { return }
        statusBarController?.actionCoordinator.resetForRepositorySwitch()
        Task { @MainActor in
            self.statusBarController?.openMainWindow()
        }
    }

    /// Removes the GitHub OAuth token the app stored before the login was
    /// removed. The item is useless without the login UI, so it is deleted
    /// once instead of lingering in the keychain.
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
