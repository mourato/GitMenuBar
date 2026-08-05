import SwiftUI

struct AIProviderManagementSheet: View {
    @EnvironmentObject private var aiProviderStore: AIProviderStore
    @EnvironmentObject private var aiCommitCoordinator: AICommitCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var editingProvider: AIProviderConfig?
    @State private var showingEditor = false
    @State private var providerToDelete: AIProviderConfig?
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Providers")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            if aiProviderStore.providers.isEmpty {
                ContentUnavailableView {
                    Label("No AI providers", systemImage: "sparkles")
                } description: {
                    Text("Add a provider to generate commit messages.")
                } actions: {
                    Button("Add Provider") { addProvider() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(aiProviderStore.providers) { provider in
                        AIProviderRowView(
                            provider: provider,
                            isDefault: aiProviderStore.preferences.defaultProviderId == provider.id,
                            onEdit: { edit(provider) },
                            onDelete: { confirmDelete(provider) }
                        )
                        if provider.id != aiProviderStore.providers.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))

                Button("Add Provider") { addProvider() }
                    .buttonStyle(.bordered)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 500)
        .sheet(isPresented: $showingEditor) {
            AIProviderEditorSheet(existingProvider: editingProvider) { provider, apiKey in
                save(provider, apiKey: apiKey)
            }
            .environmentObject(aiCommitCoordinator)
        }
        .alert("Delete provider?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deletePendingProvider() }
            Button("Cancel", role: .cancel) { providerToDelete = nil }
        } message: {
            Text("This removes the provider configuration. Its shared credential is removed only when no other provider uses it.")
        }
    }

    private func addProvider() {
        editingProvider = nil
        errorMessage = nil
        showingEditor = true
    }

    private func edit(_ provider: AIProviderConfig) {
        editingProvider = provider
        errorMessage = nil
        showingEditor = true
    }

    private func save(_ provider: AIProviderConfig, apiKey: String) -> Result<Void, Error> {
        errorMessage = nil
        let previousProvider = aiProviderStore.providers.first(where: { $0.id == provider.id })
        aiProviderStore.upsertProvider(provider)

        switch aiCommitCoordinator.saveAPIKey(apiKey, for: provider.id) {
        case .success:
            return .success(())
        case let .failure(error):
            if let previousProvider {
                aiProviderStore.upsertProvider(previousProvider)
            } else {
                aiProviderStore.deleteProvider(id: provider.id)
            }
            errorMessage = "Could not save provider. Check Keychain access and try again."
            return .failure(error)
        }
    }

    private func confirmDelete(_ provider: AIProviderConfig) {
        providerToDelete = provider
        showingDeleteConfirmation = true
    }

    private func deletePendingProvider() {
        guard let provider = providerToDelete else { return }
        providerToDelete = nil
        errorMessage = nil

        let credentialID = AIProviderCredentialID(provider: provider)
        let hasRemainingReference = aiProviderStore.providers.contains {
            $0.id != provider.id && AIProviderCredentialID(provider: $0) == credentialID
        }

        if !hasRemainingReference {
            switch aiCommitCoordinator.deleteAPIKey(for: provider.id) {
            case .success:
                break
            case .failure:
                errorMessage = "Could not delete provider. Check Keychain access and try again."
                return
            }
        }

        aiProviderStore.deleteProvider(id: provider.id)
    }
}

private func makeAIProviderManagementPreviewStore(populated: Bool) -> AIProviderStore {
    let store = AIProviderStore(dataStore: InMemoryAIProviderStoreDataStore())
    if populated {
        store.upsertProvider(AIProviderConfig(
            name: "OpenAI Team",
            type: .openAI,
            endpointURL: AIProviderType.openAI.defaultEndpoint,
            selectedModel: "gpt-5",
            availableModels: ["gpt-5"]
        ))
    }
    return store
}

#Preview("AI Provider Management") {
    let providerStore = makeAIProviderManagementPreviewStore(populated: false)
    let coordinator = AICommitCoordinator(
        providerStore: providerStore,
        keychainStore: InMemoryAIAPIKeyStore(),
        messageService: AICommitMessageService(),
        gitManager: GitManager(repositoryPathOverride: "/tmp")
    )

    AIProviderManagementSheet()
        .environmentObject(providerStore)
        .environmentObject(coordinator)
}

#Preview("AI Provider Management with providers") {
    let providerStore = makeAIProviderManagementPreviewStore(populated: true)
    let coordinator = AICommitCoordinator(
        providerStore: providerStore,
        keychainStore: InMemoryAIAPIKeyStore(),
        messageService: AICommitMessageService(),
        gitManager: GitManager(repositoryPathOverride: "/tmp")
    )

    AIProviderManagementSheet()
        .environmentObject(providerStore)
        .environmentObject(coordinator)
}
