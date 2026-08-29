import SwiftUI

struct AISettingsSectionView: View {
    @EnvironmentObject private var aiProviderStore: AIProviderStore
    @EnvironmentObject private var aiCommitCoordinator: AICommitCoordinator

    @State private var showingProviderManagement = false

    var body: some View {
        Group {
            defaultProviderPicker
            defaultModelPicker
            fallbackProviderPicker
            fallbackModelPicker
            Button("Add Provider") {
                showingProviderManagement = true
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingProviderManagement) {
            AIProviderManagementSheet()
                .environmentObject(aiProviderStore)
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
            if aiProviderStore.providers.isEmpty {
                Text("No provider configured").tag(UUID?.none)
            } else {
                ForEach(aiProviderStore.providers) { provider in
                    Text(provider.name).tag(Optional(provider.id))
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(aiProviderStore.providers.isEmpty)
    }

    private var fallbackModelPicker: some View {
        Picker(
            "Fallback Model",
            selection: Binding(
                get: { aiProviderStore.preferences.fallbackModel },
                set: { aiProviderStore.updateFallbackModel($0) }
            )
        ) {
            Text("Not configured").tag("")
            ForEach(modelsForFallbackProvider, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        .pickerStyle(.menu)
        .disabled(modelsForFallbackProvider.isEmpty)
    }

    private var fallbackProviderPicker: some View {
        Picker(
            "Fallback Provider",
            selection: Binding<UUID?>(
                get: { aiProviderStore.preferences.fallbackProviderId },
                set: { aiProviderStore.updateFallbackProvider($0) }
            )
        ) {
            Text("Default provider").tag(UUID?.none)
            ForEach(aiProviderStore.providers) { provider in
                Text(provider.name).tag(Optional(provider.id))
            }
        }
        .pickerStyle(.menu)
        .disabled(aiProviderStore.providers.isEmpty)
    }

    private var modelsForFallbackProvider: [String] {
        let provider = aiProviderStore.fallbackProvider
        if provider?.availableModels.isEmpty == false {
            return provider?.availableModels ?? []
        }

        return provider?.selectedModel.isEmpty == false ? [provider?.selectedModel ?? ""] : []
    }

    @ViewBuilder
    private var defaultModelPicker: some View {
        let provider = aiProviderStore.defaultProvider
        let models = provider?.availableModels.isEmpty == false
            ? provider?.availableModels ?? []
            : provider?.selectedModel.isEmpty == false ? [provider?.selectedModel ?? ""] : []

        Picker(
            "Default Model",
            selection: Binding(
                get: { aiProviderStore.preferences.defaultModel },
                set: { aiProviderStore.updateDefaultModel($0) }
            )
        ) {
            if models.isEmpty {
                Text("No model configured").tag("")
            } else {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(models.isEmpty)
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
