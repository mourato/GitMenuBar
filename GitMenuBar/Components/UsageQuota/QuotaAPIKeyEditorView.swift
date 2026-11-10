import SwiftUI

/// API-key lifecycle for quota providers that authenticate with a stored key:
/// visible input, show/hide, save, and removal with confirmation.
struct QuotaAPIKeyEditorView: View {
    @Environment(UsageQuotaStore.self) private var usageQuotaStore
    @Environment(UsageQuotaPresentationPreferences.self) private var preferences
    @Environment(AICommitCoordinator.self) private var aiCommitCoordinator

    let providerID: UsageProviderID

    @State private var draft = ""
    @State private var isRevealed = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirm = false

    private var savedSuffix: String? {
        preferences.quotaKeySuffixes[providerID]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Text(keyCaption)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                keyField
                    .textFieldStyle(.roundedBorder)
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: WorkbenchMetrics.iconHitTarget, minHeight: WorkbenchMetrics.iconHitTarget)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isRevealed ? "Hide key" : "Show key")
            }
            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Button("Save", action: saveKey)
                    .buttonStyle(.borderless)
                    .disabled(draftTrimmed.isEmpty)
                    .accessibilityLabel("Save \(providerID.displayName) key")
                if savedSuffix != nil {
                    Button("Remove", role: .destructive, action: confirmRemoveKey)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(providerID.displayName) key")
                }
            }
            if let savedSuffix {
                Text("Saved key ending in \(savedSuffix).")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: refreshPresence)
        .onChange(of: usageQuotaStore.snapshots) { _, _ in
            refreshPresence()
        }
        .alert(
            "Remove \(providerID.displayName) key?",
            isPresented: $showingDeleteConfirm
        ) {
            Button("Remove", role: .destructive, action: removeKey)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The AI provider using this key, if any, also stops working. Quotas fall back to a local estimate or become unavailable.")
        }
    }

    private var keyField: some View {
        Group {
            if isRevealed {
                TextField("Paste the \(providerID.displayName) key", text: $draft)
            } else {
                SecureField("Paste the \(providerID.displayName) key", text: $draft)
            }
        }
        .accessibilityLabel("\(providerID.displayName) API key")
    }

    private var keyCaption: String {
        switch providerID {
        case .opencodeGo:
            "OPENCODE_API_KEY, saved in Keychain"
        case .openrouter:
            "OpenRouter key, saved in Keychain"
        case .claudeCode, .codex, .cursor, .gemini, .antigravity:
            "API key, saved in Keychain"
        }
    }

    private var draftTrimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveKey() {
        guard let credentialID = providerID.quotaCredentialID, !draftTrimmed.isEmpty else { return }
        switch aiCommitCoordinator.saveQuotaAPIKey(draftTrimmed, for: credentialID) {
        case .success:
            draft = ""
            errorMessage = nil
            refreshPresence()
            usageQuotaStore.refresh(reason: .manual)
        case .failure:
            errorMessage = "Could not save in Keychain. Check Keychain access and try again."
        }
    }

    private func confirmRemoveKey() {
        showingDeleteConfirm = true
    }

    private func removeKey() {
        guard let credentialID = providerID.quotaCredentialID else { return }
        switch aiCommitCoordinator.deleteQuotaAPIKey(for: credentialID) {
        case .success:
            errorMessage = nil
            refreshPresence()
            usageQuotaStore.refresh(reason: .manual)
        case .failure:
            errorMessage = "Could not remove from Keychain. Check Keychain access and try again."
        }
    }

    private func refreshPresence() {
        preferences.refreshQuotaKeyPresence()
    }
}

#if DEBUG
    #Preview("Quota API Key Editor") {
        let keychainStore = InMemoryAIAPIKeyStore(storage: [.opencodego: "test-key-1234"])
        let providerStore = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
        let coordinator = AICommitCoordinator(
            providerStore: providerStore,
            keychainStore: keychainStore,
            messageService: AICommitMessageService(),
            gitManager: GitManager(repositoryPathOverride: "/tmp")
        )
        let preferences = UsageQuotaPresentationPreferences(keyStore: keychainStore)
        preferences.refreshQuotaKeyPresence()

        return QuotaAPIKeyEditorView(providerID: .opencodeGo)
            .environment(UsageQuotaStore(providers: []))
            .environment(preferences)
            .environment(coordinator)
            .padding()
            .frame(width: 420)
    }
#endif
