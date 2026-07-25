import AppKit
import SwiftUI

struct GeneralSettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.autoHideMainWindowOnBlur) private var autoHideMainWindowOnBlur =
        MainWindowPreferences.defaultAutoHideOnBlur
    @AppStorage(AppPreferences.Keys.toggleShortcutUsesMouseMonitor)
    private var toggleShortcutUsesMouseMonitor =
        MainWindowPreferences.defaultToggleShortcutUsesMouseMonitor
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    let loginItemManager: LoginItemManager

    var body: some View {
        SettingsFormPage {
            SettingsFormSectionHeader(title: "General", icon: "gearshape")
        } content: {
            Section {
                Toggle(
                    "Open at Login",
                    isOn: Binding(
                        get: { loginItemManager.isEnabled },
                        set: { newValue in
                            loginItemManager.isEnabled = newValue
                            loginItemManager.setLoginItem(enabled: newValue)
                        }
                    )
                )
                .toggleStyle(.switch)

                Toggle("Auto-hide window when focus is lost", isOn: $autoHideMainWindowOnBlur)
                    .toggleStyle(.switch)

                Toggle("Show window on monitor with mouse pointer", isOn: $toggleShortcutUsesMouseMonitor)
                    .toggleStyle(.switch)
            } header: {
                SettingsFormSectionHeader(title: "App Behavior", icon: "app.badge")
            }

            Section {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: {
                            AppPreferences.AppearanceMode.resolve(rawValue: appearanceMode)
                        },
                        set: { newValue in
                            appearanceMode = newValue.rawValue
                        }
                    )
                ) {
                    ForEach(AppPreferences.AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                SettingsFormSectionHeader(title: "Appearance", icon: "paintbrush")
            }

            Section {
                Button("Quit GitMenuBar") {
                    NSApplication.shared.terminate(nil)
                }
                .workbenchGhost()
            } header: {
                SettingsFormSectionHeader(title: "App", icon: "power")
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        SettingsAppearance.preferredColorScheme(for: appearanceMode)
    }
}

struct GitSettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.showFullPathInRecents) private var showFullPathInRecents = false
    @AppStorage(AppPreferences.Keys.hideCommitMessageField) private var hideCommitMessageField = false
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    @State private var repositoryPath = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
    @State private var recentPaths = RecentProjectsStore().recentPaths()
    @State private var showWipeConfirmation = false
    @State private var isWiping = false
    @State private var wipeError: String?

    let gitManager: GitManager
    let githubAuthManager: GitHubAuthManager
    let onSetAutoHideSuspended: (Bool) -> Void
    let onRequestCreateRepo: (String) -> Void

    private let recentProjectsStore = RecentProjectsStore()

    var body: some View {
        SettingsFormPage {
            SettingsFormSectionHeader(title: "Git", icon: "arrow.triangle.branch")
        } content: {
            Section {
                Toggle("Hide commit message field", isOn: $hideCommitMessageField)
                    .toggleStyle(.switch)
            } header: {
                SettingsFormSectionHeader(title: "Commit", icon: "text.badge.checkmark")
            } footer: {
                Text(
                    "When enabled, GitMenuBar hides the text field and prefers automatic commit messages. "
                        + "If automatic generation is unavailable, the field is shown when needed."
                )
            }

            Section {
                RepositoryPathSection(
                    repositoryPath: Binding(
                        get: { PathDisplayFormatter.abbreviatedPath(repositoryPath) },
                        set: { updateRepositoryPath(PathDisplayFormatter.expandedPath($0)) }
                    ),
                    onBrowse: browseRepository
                )
            } header: {
                SettingsFormSectionHeader(title: "Repository Path", icon: "folder")
            }

            Section {
                RecentProjectsSection(
                    recentPaths: recentPaths,
                    currentRepoPath: repositoryPath,
                    showFullPathInRecents: $showFullPathInRecents,
                    onSelectPath: selectRecentPath
                )
            } header: {
                SettingsFormSectionHeader(title: "Recent Projects", icon: "clock")
            }

            Section {
                GitHubConnectionSection(setAutoHideSuspended: onSetAutoHideSuspended)
            } header: {
                SettingsFormSectionHeader(title: "GitHub", icon: "globe")
            }

            Section {
                Button("Wipe Repository History", role: .destructive) {
                    showWipeConfirmation = true
                }
                .disabled(!githubAuthManager.isAuthenticated || gitManager.remoteUrl.isEmpty)
                .help("Reset repository to a single commit, erasing all history")
            } header: {
                SettingsFormSectionHeader(title: "Danger Zone", icon: "exclamationmark.triangle")
            } footer: {
                Text("Permanently erase commit history and reset to a single Initial commit. Current files are preserved.")
            }
        }
        .alert("Wipe Repository History?", isPresented: $showWipeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Wipe", role: .destructive) {
                wipeRepository()
            }
            .disabled(isWiping)
        } message: {
            Text(
                "This will permanently erase all commit history and reset the repository to a single \"Initial commit\". " +
                    "Your current files will be preserved. This action cannot be undone."
            )
        }
        .alert("Wipe Failed", isPresented: .init(
            get: { wipeError != nil },
            set: {
                if !$0 {
                    wipeError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wipeError ?? "An unknown error occurred.")
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private func browseRepository() {
        onSetAutoHideSuspended(true)

        DirectoryPickerService().selectDirectory(activateApp: true) { selectedPath in
            self.onSetAutoHideSuspended(false)

            guard let selectedPath else { return }
            self.applyRepositorySelection(selectedPath, mayOpenCreateRepo: true)
        }
    }

    private func selectRecentPath(_ path: String) {
        applyRepositorySelection(path, mayOpenCreateRepo: true)
    }

    private func updateRepositoryPath(_ path: String) {
        repositoryPath = path
        UserDefaults.standard.set(path, forKey: AppPreferences.Keys.gitRepoPath)
    }

    private func applyRepositorySelection(_ path: String, mayOpenCreateRepo: Bool) {
        let normalizedPath = PathDisplayFormatter.expandedPath(path)
        guard !normalizedPath.isEmpty else { return }

        updateRepositoryPath(normalizedPath)
        recentProjectsStore.add(normalizedPath)
        recentPaths = recentProjectsStore.recentPaths()

        if !gitManager.isGitRepository(at: normalizedPath), mayOpenCreateRepo, githubAuthManager.isAuthenticated {
            NSApp.keyWindow?.performClose(nil)
            onRequestCreateRepo(normalizedPath)
            return
        }

        gitManager.refresh(includeReflogHistory: false)
    }

    private func wipeRepository() {
        isWiping = true

        gitManager.wipeRepository { result in
            DispatchQueue.main.async {
                isWiping = false

                switch result {
                case .success:
                    gitManager.refresh(includeReflogHistory: false)
                case let .failure(error):
                    wipeError = error.localizedDescription
                }
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        SettingsAppearance.preferredColorScheme(for: appearanceMode)
    }
}

struct AISettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    var body: some View {
        SettingsFormPage {
            SettingsFormSectionHeader(title: "AI", icon: "sparkles")
        } content: {
            Section {
                AISettingsSectionView()
            } header: {
                SettingsFormSectionHeader(title: "AI Commit Generation", icon: "sparkles")
            }

            Section {
                UsageQuotaSettingsSection()
            } header: {
                SettingsFormSectionHeader(
                    title: "Usage Quotas",
                    icon: "gauge.with.dots.needle.33percent"
                )
            }
        }
        .preferredColorScheme(SettingsAppearance.preferredColorScheme(for: appearanceMode))
    }
}

struct ShortcutsSettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    var body: some View {
        SettingsFormPage {
            SettingsFormSectionHeader(title: "Shortcuts", icon: "keyboard")
        } content: {
            Section {
                KeyboardShortcutsSection()
            } header: {
                SettingsFormSectionHeader(title: "Keyboard Shortcuts", icon: "keyboard")
            }
        }
        .preferredColorScheme(SettingsAppearance.preferredColorScheme(for: appearanceMode))
    }
}

private enum SettingsAppearance {
    static func preferredColorScheme(for appearanceMode: String) -> ColorScheme? {
        switch AppPreferences.AppearanceMode.resolve(rawValue: appearanceMode) {
        case .systemDefault:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

#Preview("General Settings Pane") {
    GeneralSettingsPaneView(loginItemManager: LoginItemManager())
}

#Preview("Git Settings Pane") {
    let gitManager = GitManager(repositoryPathOverride: "/Users/usuario/Documents/Projects/gitmenubar")
    let githubAuthManager = GitHubAuthManager(
        tokenStore: InMemoryGitHubTokenStore(),
        preloadStoredToken: false
    )

    return GitSettingsPaneView(
        gitManager: gitManager,
        githubAuthManager: githubAuthManager,
        onSetAutoHideSuspended: { _ in },
        onRequestCreateRepo: { _ in }
    )
    .environmentObject(githubAuthManager)
}

#Preview("AI Settings Pane") {
    let gitManager = GitManager(repositoryPathOverride: "/tmp")
    let providerStore = AIProviderStore()
    let coordinator = AICommitCoordinator(
        providerStore: providerStore,
        keychainStore: InMemoryAIAPIKeyStore(),
        messageService: AICommitMessageService(),
        gitManager: gitManager
    )

    return AISettingsPaneView()
        .environmentObject(providerStore)
        .environmentObject(coordinator)
        .environmentObject(UsageQuotaStore())
}

#Preview("Shortcuts Settings Pane") {
    ShortcutsSettingsPaneView()
}
