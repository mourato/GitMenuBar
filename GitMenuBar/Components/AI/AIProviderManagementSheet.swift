import SwiftUI

struct AIProviderManagementSheet: View {
    private enum EditorPresentation: Identifiable {
        case add
        case edit(AIProviderConfig)

        var id: String {
            switch self {
            case .add:
                "add"
            case let .edit(provider):
                "edit-\(provider.id.uuidString)"
            }
        }

        var existingProvider: AIProviderConfig? {
            switch self {
            case .add:
                nil
            case let .edit(provider):
                provider
            }
        }
    }

    @EnvironmentObject private var aiProviderStore: AIProviderStore
    @EnvironmentObject private var aiCommitCoordinator: AICommitCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var editorPresentation: EditorPresentation?
    @State private var providerToDelete: AIProviderConfig?
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
                if aiProviderStore.providers.isEmpty {
                    ContentUnavailableView {
                        Label("No AI providers", systemImage: "sparkles")
                    } description: {
                        Text("Add a provider to generate commit messages.")
                    } actions: {
                        Button("Add Provider", action: addProvider)
                            .workbenchPrimary()
                    }
                } else {
                    List {
                        ForEach(aiProviderStore.providers) { provider in
                            AIProviderRowView(
                                provider: provider,
                                isDefault: aiProviderStore.preferences.defaultProviderId == provider.id,
                                onEdit: { edit(provider) },
                                onDelete: { confirmDelete(provider) }
                            )
                            .listRowInsets(EdgeInsets(
                                top: WorkbenchMetrics.microSpacing,
                                leading: 0,
                                bottom: WorkbenchMetrics.microSpacing,
                                trailing: 0
                            ))
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 320)

                    Button("Add Provider", action: addProvider)
                        .workbenchSecondary()
                }

                if let errorMessage {
                    InlineStatusBannerView(
                        banner: InlineStatusBanner(title: nil, message: errorMessage, style: .error),
                        onDismiss: { self.errorMessage = nil }
                    )
                }
            }
            .padding(WorkbenchMetrics.panelPadding)
            .navigationTitle("AI Providers")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .frame(width: 500)
        .frame(minHeight: 300)
        .sheet(item: $editorPresentation) { presentation in
            AIProviderEditorSheet(existingProvider: presentation.existingProvider) { provider, apiKey in
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
        errorMessage = nil
        editorPresentation = .add
    }

    private func edit(_ provider: AIProviderConfig) {
        errorMessage = nil
        editorPresentation = .edit(provider)
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
