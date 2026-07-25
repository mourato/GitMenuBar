import SwiftUI

struct AISettingsSectionView: View {
    @EnvironmentObject private var aiProviderStore: AIProviderStore
    @EnvironmentObject private var aiCommitCoordinator: AICommitCoordinator

    @State private var editingProvider: AIProviderConfig?
    @State private var showingProviderEditor = false

    var body: some View {
        Group {
            if aiProviderStore.providers.isEmpty {
                Text("No AI providers configured yet.")
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.secondary)
            } else {
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

            Button("Add Provider") {
                editingProvider = nil
                showingProviderEditor = true
            }
            .buttonStyle(.borderless)
            .focusable(false)

            if !aiProviderStore.providers.isEmpty {
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
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var defaultModelPicker: some View {
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
                .font(WorkbenchTypography.caption)
            }
        }
    }
}

#Preview {
    let gitManager = GitManager(repositoryPathOverride: "/tmp")
    let providerStore = AIProviderStore()
    let keychainStore = InMemoryAIAPIKeyStore()
    let coordinator = AICommitCoordinator(
        providerStore: providerStore,
        keychainStore: keychainStore,
        messageService: AICommitMessageService(),
        gitManager: gitManager
    )

    return Form {
        Section {
            AISettingsSectionView()
        } header: {
            SettingsFormSectionHeader(title: "AI Commit Generation", icon: "sparkles")
        }
    }
    .formStyle(.grouped)
    .environmentObject(providerStore)
    .environmentObject(coordinator)
    .frame(width: 560, height: 280)
}
