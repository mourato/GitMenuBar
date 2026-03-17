import SwiftUI

struct GitHubConnectionSection: View {
    @EnvironmentObject private var githubAuthManager: GitHubAuthManager

    let setAutoHideSuspended: (Bool) -> Void

    var body: some View {
        SettingsSection(title: "GitHub", systemImage: "globe") {
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
                                .foregroundColor(.green)
                            Text("Copied to clipboard")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("Enter this code on GitHub")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

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
