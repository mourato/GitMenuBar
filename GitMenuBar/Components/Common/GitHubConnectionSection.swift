import SwiftUI

struct GitHubConnectionSection: View {
    @EnvironmentObject private var githubAuthManager: GitHubAuthManager

    let setAutoHideSuspended: (Bool) -> Void

    var body: some View {
        SettingsSection(title: "GitHub", systemImage: "globe") {
            if githubAuthManager.isAuthenticated {
                HStack {
                    Text("Connected as @\(githubAuthManager.username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Disconnect") {
                        githubAuthManager.disconnect()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .macPanelSurface(cornerRadius: MacChromeMetrics.cornerRadius)
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
        VStack(spacing: 12) {
            if !githubAuthManager.userCode.isEmpty {
                VStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text(githubAuthManager.userCode)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .kerning(2)

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text("Copied to clipboard")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("Enter this code on GitHub")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Cancel") {
                        githubAuthManager.cancelAuthentication()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .macPanelSurface(cornerRadius: MacChromeMetrics.cornerRadius)
    }

    private var disconnectedView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Not connected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Connect") {
                    setAutoHideSuspended(true)
                    githubAuthManager.startDeviceFlow()
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }

            if !githubAuthManager.authError.isEmpty {
                Text(githubAuthManager.authError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .macPanelSurface(cornerRadius: MacChromeMetrics.cornerRadius)
    }
}

#Preview("GitHub Connection") {
    let authManager = GitHubAuthManager(
        tokenStore: InMemoryGitHubTokenStore(),
        preloadStoredToken: false
    )
    authManager.isAuthenticated = true
    authManager.username = "octocat"

    return GitHubConnectionSection(setAutoHideSuspended: { _ in })
        .environmentObject(authManager)
        .padding()
        .frame(width: 360)
}
