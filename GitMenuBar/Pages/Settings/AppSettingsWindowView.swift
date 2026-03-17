import AppKit
import SwiftUI

struct GeneralSettingsPaneView: View {
    @AppStorage(AppPreferences.Keys.showFullPathInRecents) private var showFullPathInRecents = false
    @AppStorage(AppPreferences.Keys.autoHideMainWindowOnBlur) private var autoHideMainWindowOnBlur =
        MainWindowPreferences.defaultAutoHideOnBlur

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
                RepositoryPathSection(
                    repositoryPath: Binding(
                        get: { PathDisplayFormatter.abbreviatedPath(repositoryPath) },
                        set: { updateRepositoryPath(PathDisplayFormatter.expandedPath($0)) }
                    ),
                    onBrowse: browseRepository
                )

                HStack {
                    Button(action: toggleOpenAtLogin) {
                        HStack(spacing: 6) {
                            Image(systemName: loginItemManager.isEnabled ? "checkmark.square" : "square")
                                .font(.system(size: 13))
                                .foregroundColor(
                                    loginItemManager.isEnabled ? .primary.opacity(0.7) : .secondary.opacity(0.5)
                                )
                            Text("Open at Login")
                        }
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Spacer()
                }
                .padding(.top, 4)

                Toggle("Auto-hide window when focus is lost", isOn: $autoHideMainWindowOnBlur)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .padding(.top, 2)

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
    }

    private func toggleOpenAtLogin() {
        loginItemManager.isEnabled.toggle()
        loginItemManager.setLoginItem(enabled: loginItemManager.isEnabled)
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

        gitManager.refresh()
    }
}

struct AccountsSettingsPaneView: View {
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
    }
}

struct ShortcutsSettingsPaneView: View {
    let gitManager: GitManager
    let githubAuthManager: GitHubAuthManager

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
                .focusable(false)
                .foregroundColor(.secondary)
                .disabled(!githubAuthManager.isAuthenticated || gitManager.remoteUrl.isEmpty)
                .help("Reset repository to a single commit, erasing all history")

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .focusable(false)
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
    }

    private func wipeRepository() {
        isWiping = true

        gitManager.wipeRepository { result in
            DispatchQueue.main.async {
                isWiping = false

                switch result {
                case .success:
                    gitManager.refresh()
                case let .failure(error):
                    wipeError = error.localizedDescription
                }
            }
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
