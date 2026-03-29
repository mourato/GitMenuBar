//
//  GitHubAuthManager.swift
//  GitMenuBar
//

import AppKit
import Foundation

struct GitHubAuthSessionSnapshot {
    let token: String?
    let username: String
}

@MainActor
class GitHubAuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var username: String = ""
    @Published var isAuthenticating: Bool = false
    @Published var userCode: String = ""
    @Published var authError: String = ""

    // Using GitHub CLI's official Client ID - no risk of account flagging!
    private let clientID = "178c6fc778ccc68e1d6a"
    private let scope = "repo delete_repo"

    private let tokenStore: any GitHubTokenStore

    // Device flow state
    private var deviceCode: String = ""
    private var pollingInterval: Int = 5
    private var authenticationTask: Task<Void, Never>?

    init(
        tokenStore: (any GitHubTokenStore)? = nil,
        preloadStoredToken: Bool? = nil
    ) {
        let usesEphemeralStores = AppExecutionContext.usesEphemeralCredentialStores
        self.tokenStore = tokenStore ?? {
            if usesEphemeralStores {
                return InMemoryGitHubTokenStore()
            }
            return CachedGitHubTokenStore(backingStore: GitHubKeychainTokenStore())
        }()
        let shouldPreloadStoredToken = preloadStoredToken ?? !usesEphemeralStores

        // Check if we have a stored token
        if shouldPreloadStoredToken, getStoredToken() != nil {
            isAuthenticated = true
            // Fetch username in background
            Task {
                await fetchUsername()
            }
        }
    }

    // MARK: - Device Flow OAuth

    /// Start the GitHub Device Flow authentication
    func startDeviceFlow() {
        authenticationTask?.cancel()
        isAuthenticating = true
        authError = ""
        userCode = ""
        deviceCode = ""
        pollingInterval = 5

        authenticationTask = Task { [weak self] in
            guard let self else { return }
            await initiateDeviceFlow()
        }
    }

    /// Step 1: Request device and user codes from GitHub
    private func initiateDeviceFlow() async {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": clientID,
            "scope": scope
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for error
                if let error = json["error"] as? String {
                    let errorDesc = json["error_description"] as? String ?? error
                    authError = errorDesc
                    isAuthenticating = false
                    authenticationTask = nil
                    return
                }

                // Extract device flow data
                guard let deviceCode = json["device_code"] as? String,
                      let userCode = json["user_code"] as? String,
                      let verificationUri = json["verification_uri"] as? String,
                      let interval = json["interval"] as? Int
                else {
                    authError = "Invalid response from GitHub"
                    isAuthenticating = false
                    authenticationTask = nil
                    return
                }

                self.deviceCode = deviceCode
                pollingInterval = interval

                self.userCode = userCode

                // Copy code to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(userCode, forType: .string)

                // Open browser to verification URL
                if let url = URL(string: verificationUri) {
                    NSWorkspace.shared.open(url)
                }

                // Start polling for the token
                await startPolling()
            }
        } catch {
            guard !Task.isCancelled else { return }
            authError = "Network error: \(error.localizedDescription)"
            isAuthenticating = false
            authenticationTask = nil
        }
    }

    /// Step 2: Poll GitHub for the access token until user authorizes
    private func startPolling() async {
        // Poll with the specified interval
        while isAuthenticating, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollingInterval) * 1_000_000_000)
            guard !Task.isCancelled, isAuthenticating else { break }

            let result = await pollForToken()

            switch result {
            case let .success(token):
                // Store token and update state
                tokenStore.saveToken(token)
                isAuthenticated = true
                isAuthenticating = false
                userCode = ""
                authenticationTask = nil
                await fetchUsername()
                return

            case .pending:
                // Keep polling
                continue

            case .slowDown:
                // Increase polling interval
                pollingInterval += 5
                continue

            case let .error(message):
                authError = message
                isAuthenticating = false
                userCode = ""
                authenticationTask = nil
                return
            }
        }

        if Task.isCancelled {
            authenticationTask = nil
        }
    }

    private enum PollResult {
        case success(String)
        case pending
        case slowDown
        case error(String)
    }

    private func pollForToken() async -> PollResult {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for success
                if let accessToken = json["access_token"] as? String {
                    return .success(accessToken)
                }

                // Check for errors
                if let error = json["error"] as? String {
                    switch error {
                    case "authorization_pending":
                        return .pending
                    case "slow_down":
                        return .slowDown
                    case "expired_token":
                        return .error("Authorization expired. Please try again.")
                    case "access_denied":
                        return .error("Access denied by user.")
                    default:
                        let desc = json["error_description"] as? String ?? error
                        return .error(desc)
                    }
                }
            }

            return .error("Invalid response from GitHub")
        } catch {
            return .error("Network error: \(error.localizedDescription)")
        }
    }

    /// Cancel the ongoing authentication
    func cancelAuthentication() {
        authenticationTask?.cancel()
        authenticationTask = nil
        isAuthenticating = false
        userCode = ""
        deviceCode = ""
        pollingInterval = 5
        authError = ""
    }

    // MARK: - Token Storage

    nonisolated func storedTokenSnapshot() -> String? {
        tokenStore.storedToken()
    }

    func getStoredToken() -> String? {
        storedTokenSnapshot()
    }

    func sessionSnapshot() -> GitHubAuthSessionSnapshot {
        GitHubAuthSessionSnapshot(
            token: storedTokenSnapshot(),
            username: username
        )
    }

    private func deleteStoredToken() {
        tokenStore.deleteStoredToken()
    }

    // MARK: - User Info

    private func fetchUsername() async {
        guard let token = getStoredToken() else { return }

        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            let login = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["login"] as? String
            if let login {
                await MainActor.run {
                    self.username = login
                }
            }
        } catch {
            print("Error fetching username: \(error)")
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        authenticationTask?.cancel()
        authenticationTask = nil
        deleteStoredToken()
        isAuthenticated = false
        username = ""
    }

    deinit {
        authenticationTask?.cancel()
    }
}
