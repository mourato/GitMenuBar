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
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var githubAuthManager: GitHubAuthManager?
    private let recentProjectsStore = RecentProjectsStore()

    func applicationDidFinishLaunching(_: Notification) {
        guard !AppExecutionContext.isRunningTests else {
            return
        }

        // Migrate keychain items to the unified domain if necessary before setting up the app
        KeychainMigrator.migrateToUnifiedDomain()

        // Hide the dock icon immediately
        NSApp.setActivationPolicy(.accessory)

        // Reset user defaults to ensure main page shows
        UserDefaults.standard.set(false, forKey: AppPreferences.Keys.showSettings)

        // Create GitHub auth manager
        githubAuthManager = GitHubAuthManager()

        // Create and show status bar controller - keep strong reference
        statusBarController = StatusBarController(githubAuthManager: githubAuthManager!)

        // Check login item status after controller is created
        statusBarController?.loginItemManager.checkLoginItemStatus()

        // Check for updates on launch
        UpdateChecker.shared.checkForUpdatesOnLaunch()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // Reopen the app if clicked while hidden
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationDidResignActive(_: Notification) {
        // When app becomes inactive, reset to main view
        UserDefaults.standard.set(false, forKey: AppPreferences.Keys.showSettings)
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

        // Check if this is a git repository
        let gitPath = (path as NSString).appendingPathComponent(".git")
        let isGitRepo = FileManager.default.fileExists(atPath: gitPath)

        if isGitRepo, githubAuthManager?.isAuthenticated == true {
            // Check if remote repo actually exists on GitHub
            statusBarController?.gitManager.remoteRepositoryExists(at: path) { [weak self] exists in
                guard let self = self else { return }

                UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
                self.recentProjectsStore.add(path)

                if exists {
                    DispatchQueue.main.async {
                        self.statusBarController?.openPopover()
                    }
                } else {
                    // Remote doesn't exist (either no remote or 404) - show create repo UI
                    DispatchQueue.main.async {
                        self.statusBarController?.openPopoverWithCreateRepo(path: path)
                    }
                }
            }
        } else if isGitRepo {
            // Git repo but not authenticated - just open normally
            UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
            recentProjectsStore.add(path)

            DispatchQueue.main.async {
                self.statusBarController?.openPopover()
            }
        } else {
            // Not a git repo at all - show create repo window if GitHub is connected
            if githubAuthManager?.isAuthenticated == true {
                UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
                recentProjectsStore.add(path)

                DispatchQueue.main.async {
                    self.statusBarController?.openPopoverWithCreateRepo(path: path)
                }
            } else {
                // Not connected to GitHub - just open normally
                UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
                recentProjectsStore.add(path)

                DispatchQueue.main.async {
                    self.statusBarController?.openPopover()
                }
            }
        }
    }
}
