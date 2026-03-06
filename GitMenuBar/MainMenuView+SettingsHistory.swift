//
//  MainMenuView+SettingsHistory.swift
//  GitMenuBar
//

import KeyboardShortcuts
import SwiftUI

extension MainMenuView {
    var settingsView: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button("Done") {
                    if let currentPath = UserDefaults.standard.string(forKey: "gitRepoPath"), !currentPath.isEmpty {
                        addToRecents(currentPath)
                        gitManager.refresh()
                    }
                    showingSettings = false
                    UserDefaults.standard.set(false, forKey: "showSettings")
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
            .padding(.top, 4)

            Divider()
                .padding(.top, 4)

            // Settings content
            ScrollView {
                VStack(spacing: 12) {
                    // Git Repository Path section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Git Repository Path")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .padding(.top, 2)

                        TextField("Select repository directory", text: Binding(
                            get: { ((UserDefaults.standard.string(forKey: "gitRepoPath") ?? "") as NSString).abbreviatingWithTildeInPath },
                            set: { newValue in
                                UserDefaults.standard.set((newValue as NSString).expandingTildeInPath, forKey: "gitRepoPath")
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                        Button("Browse...") {
                            selectDirectory()
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)
                    }

                    // Open at Login section
                    HStack {
                        Button(action: {
                            loginItemManager.isEnabled.toggle()
                            loginItemManager.setLoginItem(enabled: loginItemManager.isEnabled)
                        }) {
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

                    // GitHub Connection section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("GitHub")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .padding(.top, 4)

                        if githubAuthManager.isAuthenticated {
                            HStack {
                                Text("Connected as @\(githubAuthManager.username)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Disconnect") {
                                    githubAuthManager.disconnect()
                                }
                                .buttonStyle(.borderless)
                                .focusable(false)
                                .font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        } else if githubAuthManager.isAuthenticating {
                            // Device Flow: Show user code
                            VStack(spacing: 12) {
                                if !githubAuthManager.userCode.isEmpty {
                                    VStack(spacing: 8) {
                                        // Code display - prominent and centered
                                        VStack(spacing: 4) {
                                            Text(githubAuthManager.userCode)
                                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.primary)
                                                .kerning(2)

                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.green)
                                                Text("Copied to clipboard")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        // Status
                                        Text("Enter this code on GitHub")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)

                                        // Cancel button
                                        Button("Cancel") {
                                            githubAuthManager.cancelAuthentication()
                                        }
                                        .buttonStyle(.borderless)
                                        .focusable(false)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Connecting...")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(6)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Not connected")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Connect") {
                                        // Keep popover open while browser is in focus
                                        togglePopoverBehavior()
                                        githubAuthManager.startDeviceFlow()
                                    }
                                    .buttonStyle(.borderless)
                                    .focusable(false)
                                    .font(.system(size: 11))
                                }
                                if !githubAuthManager.authError.isEmpty {
                                    Text(githubAuthManager.authError)
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                    .padding(.top, 4)
                    .onChange(of: githubAuthManager.isAuthenticating) { _, isAuthenticating in
                        // When authentication ends (success or cancel), revert popover behavior
                        if !isAuthenticating {
                            togglePopoverBehavior()
                        }
                    }

                    AISettingsSectionView()
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Keyboard Shortcuts")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .padding(.top, 4)

                        HStack {
                            Text("Open Popover")
                                .font(.system(size: 11))
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .togglePopover)
                                .labelsHidden()
                        }

                        HStack {
                            Text("Commit")
                                .font(.system(size: 11))
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .commit)
                                .labelsHidden()
                        }

                        HStack {
                            Text("Sync")
                                .font(.system(size: 11))
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .sync)
                                .labelsHidden()
                        }

                        HStack {
                            Spacer()
                            Button("Reset to Defaults") {
                                KeyboardShortcuts.reset(.togglePopover)
                                KeyboardShortcuts.reset(.commit)
                                KeyboardShortcuts.reset(.sync)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        }
                    }
                    .padding(.top, 4)

                    if !recentPaths.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text("Recently Used")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showFullPathInRecents.toggle()
                                }
                            }
                            .onHover { inside in
                                if inside {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .help("Click to toggle between full path and project name")

                            ForEach(recentPaths.filter { $0 != UserDefaults.standard.string(forKey: "gitRepoPath") }.prefix(5), id: \.self) { path in
                                let abbreviatedPath = (path as NSString).abbreviatingWithTildeInPath
                                let displayName = showFullPathInRecents ? abbreviatedPath : URL(fileURLWithPath: path).lastPathComponent
                                RecentPathRowView(
                                    displayText: displayName,
                                    fullPath: abbreviatedPath,
                                    onTap: {
                                        switchRepository(path: path, closeSettingsAfterRefresh: true)
                                    }
                                )
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            HStack {
                Button("Wipe") {
                    showWipeConfirmation = true
                }
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

    func createRepoView(folderPath: String) -> some View {
        VStack(spacing: 12) {
            // Header - matching settings/history style
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("Create Repository")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button("Cancel") {
                    createRepoPath = nil
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
            .padding(.top, 4)

            Divider()
                .padding(.top, 4)

            // Content
            CreateRepoContentView(
                folderPath: folderPath,
                onDismiss: { createRepoPath = nil },
                onSuccess: { path in
                    UserDefaults.standard.set(path, forKey: "gitRepoPath")
                    addToRecents(path)
                    createRepoPath = nil
                    // Force immediate refresh to show new remote URL
                    gitManager.updateRemoteUrl()
                    gitManager.refresh()
                }
            )
            .environmentObject(gitManager)
            .environmentObject(githubAuthManager)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    var historyView: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                    Text("History")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                Spacer()
                Button("Done") {
                    showingHistory = false
                }
                .buttonStyle(.borderless)
                .focusable(false)
            }
            .padding(.top, 4)

            Divider()
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(gitManager.commitHistory) { commit in
                        CommitRowView(
                            commit: commit,
                            isCurrentCommit: commit.id == gitManager.currentHash,
                            isFutureCommit: isCommitInFuture(commit),
                            onTap: {
                                if commit.id != gitManager.currentHash {
                                    gitManager.resetToCommit(commit.id)
                                }
                            }
                        )

                        Divider()
                    }
                }
            }
            .frame(height: 200) // Smaller height as requested
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

#Preview("Settings & History") {
    MainMenuPreviewHarness {
        MainMenuView(initialScreen: .settings)
    }
}
