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
    @AppStorage(AppPreferences.Keys.hideCommitMessageField) private var hideCommitMessageField = false
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    let gitManager: GitManager
    let githubAuthManager: GitHubAuthManager
    let onSetAutoHideSuspended: (Bool) -> Void

    var body: some View {
        SettingsFormPage {
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
                GitHubConnectionSection(setAutoHideSuspended: onSetAutoHideSuspended)
            } header: {
                SettingsFormSectionHeader(title: "GitHub", icon: "globe")
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        SettingsAppearance.preferredColorScheme(for: appearanceMode)
    }
}

struct AISettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    var body: some View {
        SettingsFormPage {
            Section {
                AISettingsSectionView()
            } header: {
                SettingsFormSectionHeader(title: "AI Commit Generation", icon: "sparkles")
            }

            Section {
                CompanionCLIInstallSectionView()
            } header: {
                SettingsFormSectionHeader(title: "Companion CLI", icon: "terminal")
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
            nil
        case .light:
            .light
        case .dark:
            .dark
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
        onSetAutoHideSuspended: { _ in }
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
