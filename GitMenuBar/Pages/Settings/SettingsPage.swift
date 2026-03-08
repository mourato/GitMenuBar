import AppKit
import SwiftUI

struct SettingsPageView: View {
    @EnvironmentObject private var gitManager: GitManager
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @EnvironmentObject private var githubAuthManager: GitHubAuthManager

    let repositoryPath: String
    let recentPaths: [String]
    @Binding var showFullPathInRecents: Bool
    let onRepositoryPathChanged: (String) -> Void
    let onBrowse: () -> Void
    let onSelectRecentPath: (String) -> Void
    let onDone: () -> Void
    let onTogglePopoverBehavior: () -> Void
    let onWipe: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            InlinePageHeader(
                title: "Settings",
                systemImage: "gear",
                actionTitle: "Done",
                onAction: onDone
            )

            Divider()
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 12) {
                    RepositoryPathSection(
                        repositoryPath: Binding(
                            get: { PathDisplayFormatter.abbreviatedPath(repositoryPath) },
                            set: { onRepositoryPathChanged(PathDisplayFormatter.expandedPath($0)) }
                        ),
                        onBrowse: onBrowse
                    )

                    HStack {
                        Button(action: toggleOpenAtLogin) {
                            HStack(spacing: 6) {
                                Image(systemName: loginItemManager.isEnabled ? "checkmark.square" : "square")
                                    .font(.system(size: 13))
                                    .foregroundColor(loginItemManager.isEnabled ? .primary.opacity(0.7) : .secondary.opacity(0.5))
                                Text("Open at Login")
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Spacer()
                    }
                    .padding(.top, 4)

                    GitHubConnectionSection(onTogglePopoverBehavior: onTogglePopoverBehavior)

                    AISettingsSectionView()
                        .padding(.top, 4)

                    KeyboardShortcutsSection()
                        .padding(.top, 4)

                    RecentProjectsSection(
                        recentPaths: recentPaths,
                        currentRepoPath: repositoryPath,
                        showFullPathInRecents: $showFullPathInRecents,
                        onSelectPath: onSelectRecentPath
                    )
                }
            }

            HStack {
                Button("Wipe", action: onWipe)
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
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func toggleOpenAtLogin() {
        loginItemManager.isEnabled.toggle()
        loginItemManager.setLoginItem(enabled: loginItemManager.isEnabled)
    }
}

private struct SettingsPagePreviewContainer: View {
    @State private var showFullPathInRecents = false

    var body: some View {
        MainMenuPreviewHarness(width: 420) {
            SettingsPageView(
                repositoryPath: NSHomeDirectory(),
                recentPaths: [
                    NSHomeDirectory(),
                    "/Users/usuario/Documents/Projects/gitmenubar",
                    "/tmp/example-repository"
                ],
                showFullPathInRecents: $showFullPathInRecents,
                onRepositoryPathChanged: { _ in },
                onBrowse: {},
                onSelectRecentPath: { _ in },
                onDone: {},
                onTogglePopoverBehavior: {},
                onWipe: {}
            )
        }
    }
}

#Preview("Settings Page") {
    SettingsPagePreviewContainer()
}
