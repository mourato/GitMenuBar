import SwiftUI

struct GitHubConnectionSection: View {
    @EnvironmentObject private var githubAuthManager: GitHubAuthManager
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let setAutoHideSuspended: (Bool) -> Void

    var body: some View {
        Group {
            if githubAuthManager.isAuthenticated {
                HStack {
                    Text("Connected as @\(githubAuthManager.username)")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Disconnect") {
                        githubAuthManager.disconnect()
                    }
                    .buttonStyle(.borderless)
                    .font(WorkbenchTypography.caption)
                }
                .padding(.horizontal, WorkbenchMetrics.compactSpacing)
                .padding(.vertical, WorkbenchMetrics.microSpacing)
                .githubConnectionCardChrome(contrast: colorSchemeContrast)
            } else if githubAuthManager.isAuthenticating {
                authenticatingView
            } else {
                disconnectedView
            }
        }
        .onChange(of: githubAuthManager.isAuthenticating) { _, isAuthenticating in
            setAutoHideSuspended(isAuthenticating)
        }
    }

    private var authenticatingView: some View {
        VStack(spacing: WorkbenchMetrics.sectionSpacing) {
            if !githubAuthManager.userCode.isEmpty {
                VStack(spacing: WorkbenchMetrics.compactSpacing) {
                    VStack(spacing: WorkbenchMetrics.microSpacing) {
                        Text(githubAuthManager.userCode)
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.primary)
                            .kerning(2)

                        HStack(spacing: WorkbenchMetrics.microSpacing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                            Text("Copied to clipboard")
                                .font(WorkbenchTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Enter this code on GitHub")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)

                    Button("Cancel") {
                        githubAuthManager.cancelAuthentication()
                    }
                    .buttonStyle(.borderless)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting...")
                        .font(WorkbenchTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WorkbenchMetrics.sectionSpacing)
        .padding(.horizontal, WorkbenchMetrics.sectionSpacing)
        .githubConnectionCardChrome(contrast: colorSchemeContrast)
    }

    private var disconnectedView: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            HStack {
                Text("Not connected")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Connect") {
                    setAutoHideSuspended(true)
                    githubAuthManager.startDeviceFlow()
                }
                .buttonStyle(.borderedProminent)
                .font(WorkbenchTypography.caption)
            }

            if !githubAuthManager.authError.isEmpty {
                Text(githubAuthManager.authError)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, WorkbenchMetrics.compactSpacing)
        .padding(.vertical, WorkbenchMetrics.microSpacing)
        .githubConnectionCardChrome(contrast: colorSchemeContrast)
    }
}

private struct GitHubConnectionCardChromeModifier: ViewModifier {
    let contrast: ColorSchemeContrast

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(WorkbenchPalette.neutralBorder(contrast: contrast), lineWidth: 1)
            )
    }
}

private extension View {
    func githubConnectionCardChrome(contrast: ColorSchemeContrast) -> some View {
        modifier(GitHubConnectionCardChromeModifier(contrast: contrast))
    }
}

#Preview("GitHub Connection") {
    let authManager = GitHubAuthManager(
        tokenStore: InMemoryGitHubTokenStore(),
        preloadStoredToken: false
    )
    authManager.isAuthenticated = true
    authManager.username = "octocat"

    return Form {
        Section {
            GitHubConnectionSection(setAutoHideSuspended: { _ in })
        } header: {
            SettingsFormSectionHeader(title: "GitHub", icon: "globe")
        }
    }
    .formStyle(.grouped)
    .environmentObject(authManager)
    .frame(width: 560, height: 180)
}
