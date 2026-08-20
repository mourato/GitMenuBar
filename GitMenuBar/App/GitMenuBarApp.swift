//
//  GitMenuBarApp.swift
//  GitMenuBar
//

import AppKit
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
            GitMenuBarCommandMenus(commandCenter: appDelegate.appCommandCenter)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appCommandCenter = AppCommandCenter()
    var statusBarController: StatusBarController?
    var githubAuthManager: GitHubAuthManager?

    @MainActor
    func showSettingsWindow() {
        statusBarController?.showSettingsWindow()
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !AppExecutionContext.isRunningTests else {
            return
        }

        // Migrate keychain items to the unified domain if necessary before setting up the app
        KeychainMigrator.migrateToUnifiedDomain()

        // Hide the dock icon immediately
        NSApp.setActivationPolicy(.accessory)

        // Create GitHub auth manager
        let authManager = GitHubAuthManager()
        githubAuthManager = authManager

        // Create and show status bar controller - keep strong reference
        statusBarController = StatusBarController(
            githubAuthManager: authManager,
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

    // swiftlint:disable:next cyclomatic_complexity
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

        // Check if this is a git repository
        let gitPath = (path as NSString).appendingPathComponent(".git")
        let isGitRepo = FileManager.default.fileExists(atPath: gitPath)
        guard canSwitchRepository(to: path) else { return }

        if isGitRepo, githubAuthManager?.isAuthenticated == true {
            // Check if remote repo actually exists on GitHub
            statusBarController?.gitManager.remoteRepositoryExists(at: path) { [weak self] exists in
                guard let self else { return }

                guard canSwitchRepository(to: path) else { return }

                guard let selection = statusBarController?.repositorySelectionCoordinator.select(path: path) else {
                    return
                }
                guard case let .selected(selectedPath) = selection else { return }

                if exists {
                    DispatchQueue.main.async {
                        self.statusBarController?.openMainWindow()
                    }
                } else {
                    // Remote doesn't exist (either no remote or 404) - show create repo UI
                    DispatchQueue.main.async {
                        self.statusBarController?.openMainWindowWithCreateRepo(path: selectedPath)
                    }
                }
            }
        } else {
            guard let selection = statusBarController?.repositorySelectionCoordinator.select(
                path: path,
                allowsNonGitSelection: githubAuthManager?.isAuthenticated != true
            ) else { return }

            if case let .requiresRepositoryCreation(candidatePath) = selection {
                DispatchQueue.main.async {
                    self.statusBarController?.openMainWindowWithCreateRepo(path: candidatePath)
                }
            } else if case .selected = selection {
                DispatchQueue.main.async {
                    self.statusBarController?.openMainWindow()
                }
            }
        }
    }

    private func canSwitchRepository(to path: String) -> Bool {
        statusBarController?.actionCoordinator.canSwitchRepository(to: path) ?? true
    }
}
