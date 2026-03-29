import AppKit
import SwiftUI

struct GeneralSettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.showFullPathInRecents) private var showFullPathInRecents = false
    @AppStorage(AppPreferences.Keys.autoHideMainWindowOnBlur) private var autoHideMainWindowOnBlur =
        MainWindowPreferences.defaultAutoHideOnBlur
    @AppStorage(AppPreferences.Keys.toggleShortcutUsesMouseMonitor)
    private var toggleShortcutUsesMouseMonitor =
        MainWindowPreferences.defaultToggleShortcutUsesMouseMonitor
    @AppStorage(AppPreferences.Keys.hideCommitMessageField) private var hideCommitMessageField = false
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    @State private var repositoryPath = UserDefaults.standard.string(forKey: AppPreferences.Keys.gitRepoPath) ?? ""
    @State private var recentPaths = RecentProjectsStore().recentPaths()

    let gitManager: GitManager
    let loginItemManager: LoginItemManager
    let githubAuthManager: GitHubAuthManager
    let onSetAutoHideSuspended: (Bool) -> Void
    let onRequestCreateRepo: (String) -> Void

    private let recentProjectsStore = RecentProjectsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("Open at Login")
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { loginItemManager.isEnabled },
                            set: { newValue in
                                loginItemManager.isEnabled = newValue
                                loginItemManager.setLoginItem(enabled: newValue)
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Open at Login")
                }

                HStack {
                    Text("Auto-hide window when focus is lost")
                    Spacer()
                    Toggle("", isOn: $autoHideMainWindowOnBlur)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Auto-hide window when focus is lost")
                }

                HStack {
                    Text("Show window on monitor with mouse pointer")
                    Spacer()
                    Toggle(
                        "",
                        isOn: $toggleShortcutUsesMouseMonitor
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Show window on monitor with mouse pointer")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hide commit message field")
                        Spacer()
                        Toggle("", isOn: $hideCommitMessageField)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .accessibilityLabel("Hide commit message field")
                    }

                    Text(
                        "When enabled, GitMenuBar hides the text field and prefers automatic commit messages. If automatic generation is unavailable, the field is shown when needed."
                    )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                appearancePicker

                Divider()

                RepositoryPathSection(
                    repositoryPath: Binding(
                        get: { PathDisplayFormatter.abbreviatedPath(repositoryPath) },
                        set: { updateRepositoryPath(PathDisplayFormatter.expandedPath($0)) }
                    ),
                    onBrowse: browseRepository
                )

                Divider()

                RecentProjectsSection(
                    recentPaths: recentPaths,
                    currentRepoPath: repositoryPath,
                    showFullPathInRecents: $showFullPathInRecents,
                    onSelectPath: selectRecentPath
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 420, minHeight: 700)
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

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Appearance")
                .font(.system(size: 13, weight: .medium))

            Picker(
                "",
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
            .accessibilityLabel("Appearance")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preferredColorScheme: ColorScheme? {
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

struct AccountsSettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue
    let onSetAutoHideSuspended: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GitHubConnectionSection(setAutoHideSuspended: onSetAutoHideSuspended)

                AISettingsSectionView()
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 420, minHeight: 700)
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
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

struct ShortcutsSettingsPaneView: View {
    let gitManager: GitManager
    let githubAuthManager: GitHubAuthManager
    @AppStorage(AppPreferences.Keys.appearanceMode) private var appearanceMode = AppPreferences.AppearanceMode.defaultMode.rawValue

    @State private var showWipeConfirmation = false
    @State private var isWiping = false
    @State private var wipeError: String?

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    KeyboardShortcutsSection()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Divider()

            HStack {
                Button("Wipe", action: {
                    showWipeConfirmation = true
                })
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .disabled(!githubAuthManager.isAuthenticated || gitManager.remoteUrl.isEmpty)
                .help("Reset repository to a single commit, erasing all history")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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
            set: { if !$0 { wipeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wipeError ?? "An unknown error occurred.")
        }
        .frame(minWidth: 420, minHeight: 700)
        .preferredColorScheme(preferredColorScheme)
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
    let gitManager = GitManager(repositoryPathOverride: "/Users/usuario/Documents/Projects/gitmenubar")
    let loginItemManager = LoginItemManager()
    let githubAuthManager = GitHubAuthManager(
        tokenStore: InMemoryGitHubTokenStore(),
        preloadStoredToken: false
    )

    return GeneralSettingsPaneView(
        gitManager: gitManager,
        loginItemManager: loginItemManager,
        githubAuthManager: githubAuthManager,
        onSetAutoHideSuspended: { _ in },
        onRequestCreateRepo: { _ in }
    )
}
