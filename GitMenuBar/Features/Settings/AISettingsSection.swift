import SwiftUI

struct AISettingsSectionView: View {
    @EnvironmentObject private var aiProviderStore: AIProviderStore
    @EnvironmentObject private var aiCommitCoordinator: AICommitCoordinator

    @State private var editingProvider: AIProviderConfig?
    @State private var showingProviderEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text("AI Commit Generation")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .padding(.top, 4)

            if aiProviderStore.providers.isEmpty {
                Text("No AI providers configured yet.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(aiProviderStore.providers) { provider in
                        AIProviderRowView(
                            provider: provider,
                            isDefault: aiProviderStore.preferences.defaultProviderId == provider.id,
                            onEdit: {
                                editingProvider = provider
                                showingProviderEditor = true
                            },
                            onDelete: {
                                aiCommitCoordinator.deleteAPIKey(for: provider.id)
                                aiProviderStore.deleteProvider(id: provider.id)
                            }
                        )
                    }
                }
            }

            Button("Add Provider") {
                editingProvider = nil
                showingProviderEditor = true
            }
            .buttonStyle(.borderless)
            .focusable(false)

            if !aiProviderStore.providers.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                defaultProviderPicker

                defaultModelPicker
            }
        }
        .sheet(isPresented: $showingProviderEditor) {
            AIProviderEditorSheet(
                existingProvider: editingProvider,
                onSave: { provider, apiKey in
                    aiProviderStore.upsertProvider(provider)
                    aiCommitCoordinator.saveAPIKey(apiKey, for: provider.id)
                }
            )
            .environmentObject(aiCommitCoordinator)
        }
    }

    private var defaultProviderPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Default Provider")
                .font(.system(size: 11, weight: .medium))

            Picker(
                "Default Provider",
                selection: Binding<UUID?>(
                    get: { aiProviderStore.preferences.defaultProviderId },
                    set: { aiProviderStore.updateDefaultProvider($0) }
                )
            ) {
                ForEach(aiProviderStore.providers) { provider in
                    Text(provider.name).tag(Optional(provider.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var defaultModelPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Default Model")
                .font(.system(size: 11, weight: .medium))

            if let provider = aiProviderStore.defaultProvider {
                let models = provider.availableModels.isEmpty
                    ? [provider.selectedModel].filter { !$0.isEmpty }
                    : provider.availableModels

                if !models.isEmpty {
                    Picker(
                        "Default Model",
                        selection: Binding(
                            get: {
                                let current = aiProviderStore.preferences.defaultModel
                                return current.isEmpty ? models[0] : current
                            },
                            set: { aiProviderStore.updateDefaultModel($0) }
                        )
                    ) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } else {
                    TextField(
                        "Model name",
                        text: Binding(
                            get: { aiProviderStore.preferences.defaultModel },
                            set: { aiProviderStore.updateDefaultModel($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                }
            }
        }
    }
}

#Preview {
    let gitManager = GitManager(repositoryPathOverride: "/tmp")
    let providerStore = AIProviderStore()
    let keychainStore = AIKeychainStore()
    let coordinator = AICommitCoordinator(
        providerStore: providerStore,
        keychainStore: keychainStore,
        messageService: AICommitMessageService(),
        gitManager: gitManager
    )

    return AISettingsSectionView()
        .environmentObject(providerStore)
        .environmentObject(coordinator)
        .padding()
        .frame(width: 420)
}
