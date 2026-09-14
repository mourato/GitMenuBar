import SwiftUI

struct AISettingsSectionView: View {
    @EnvironmentObject private var aiProviderStore: AIProviderStore
    @EnvironmentObject private var aiCommitCoordinator: AICommitCoordinator
    @EnvironmentObject private var chatGPTSubscription: ChatGPTSubscriptionManager

    @State private var showingProviderManagement = false

    var body: some View {
        Group {
            chatGPTAccountControls
            defaultProviderPicker
            defaultModelPicker
            defaultReasoningPicker
            fallbackProviderPicker
            fallbackModelPicker
            fallbackReasoningPicker
            Button("Add Provider") {
                showingProviderManagement = true
            }
            .buttonStyle(.borderless)
        }
        .task(id: aiProviderStore.preferences.chatGPTEnabled) {
            if aiProviderStore.preferences.chatGPTEnabled {
                await chatGPTSubscription.refresh().value
            }
        }
        .sheet(isPresented: $showingProviderManagement) {
            AIProviderManagementSheet()
                .environmentObject(aiProviderStore)
                .environmentObject(aiCommitCoordinator)
        }
    }

    private var chatGPTAccountControls: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.microSpacing) {
            Toggle(
                "Use ChatGPT account",
                isOn: Binding(
                    get: { aiProviderStore.preferences.chatGPTEnabled },
                    set: { enabled in
                        aiProviderStore.updateChatGPTEnabled(enabled)
                        if !enabled {
                            chatGPTSubscription.stop()
                        }
                    }
                )
            )
            .toggleStyle(.switch)

            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Text(chatGPTSubscription.phase.title)
                    .foregroundStyle(.secondary)
                if let account = chatGPTSubscription.account {
                    Text(account.email ?? account.planTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if aiProviderStore.preferences.chatGPTEnabled {
                    Button("Refresh") {
                        _ = chatGPTSubscription.refresh()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.caption)

            if case .signedOut = chatGPTSubscription.phase {
                Text("Sign in with `codex login`, then refresh this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var defaultProviderPicker: some View {
        Picker(
            "Default Provider",
            selection: Binding<AICommitProviderSelection?>(
                get: { aiProviderStore.defaultProviderSelection },
                set: { aiProviderStore.updateDefaultSelection($0) }
            )
        ) {
            Text("ChatGPT account").tag(Optional(AICommitProviderSelection.chatGPT))
            ForEach(aiProviderStore.providers) { provider in
                Text(provider.name).tag(Optional(AICommitProviderSelection.api(provider.id)))
            }
            if aiProviderStore.defaultProviderSelection == nil {
                Text("No provider configured").tag(AICommitProviderSelection?.none)
            }
        }
        .pickerStyle(.menu)
        .disabled(!aiProviderStore.preferences.chatGPTEnabled && aiProviderStore.providers.isEmpty)
    }

    private var fallbackProviderPicker: some View {
        Picker(
            "Fallback Provider",
            selection: Binding(
                get: { aiProviderStore.fallbackProviderSelection },
                set: { aiProviderStore.updateFallbackSelection($0) }
            )
        ) {
            Text("Default provider").tag(AICommitProviderSelection.defaultProvider)
            Text("ChatGPT account").tag(AICommitProviderSelection.chatGPT)
            ForEach(aiProviderStore.providers) { provider in
                Text(provider.name).tag(AICommitProviderSelection.api(provider.id))
            }
        }
        .pickerStyle(.menu)
        .disabled(aiProviderStore.providers.isEmpty && !aiProviderStore.preferences.chatGPTEnabled)
    }

    @ViewBuilder
    private var defaultModelPicker: some View {
        if aiProviderStore.preferences.defaultUsesChatGPT {
            modelPicker(
                title: "Default Model",
                models: chatGPTSubscription.models,
                selection: Binding(
                    get: { aiProviderStore.preferences.defaultModel },
                    set: { aiProviderStore.updateDefaultModel($0) }
                )
            )
        } else {
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

    @ViewBuilder
    private var fallbackModelPicker: some View {
        if aiProviderStore.usesChatGPTForFallback {
            modelPicker(
                title: "Fallback Model",
                models: chatGPTSubscription.models,
                selection: Binding(
                    get: { aiProviderStore.preferences.fallbackModel },
                    set: { aiProviderStore.updateFallbackModel($0) }
                )
            )
        } else {
            let provider = aiProviderStore.fallbackProvider
            let models = provider?.availableModels.isEmpty == false
                ? provider?.availableModels ?? []
                : provider?.selectedModel.isEmpty == false ? [provider?.selectedModel ?? ""] : []
            Picker(
                "Fallback Model",
                selection: Binding(
                    get: { aiProviderStore.preferences.fallbackModel },
                    set: { aiProviderStore.updateFallbackModel($0) }
                )
            ) {
                Text("Not configured").tag("")
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .pickerStyle(.menu)
            .disabled(models.isEmpty)
        }
    }

    @ViewBuilder
    private var defaultReasoningPicker: some View {
        if aiProviderStore.preferences.defaultUsesChatGPT,
           let model = chatGPTSubscription.models.first(where: { $0.id == aiProviderStore.preferences.defaultModel }),
           !model.efforts.isEmpty
        {
            reasoningPicker(for: model)
        }
    }

    @ViewBuilder
    private var fallbackReasoningPicker: some View {
        if aiProviderStore.usesChatGPTForFallback,
           let model = chatGPTSubscription.models.first(where: { $0.id == aiProviderStore.preferences.fallbackModel }),
           !model.efforts.isEmpty
        {
            reasoningPicker(for: model)
        }
    }

    private func modelPicker(
        title: String,
        models: [ChatGPTSubscription.Model],
        selection: Binding<String>
    ) -> some View {
        Picker(title, selection: selection) {
            if models.isEmpty {
                Text("No subscription models found").tag("")
            } else {
                ForEach(models) { model in
                    Text(model.name).tag(model.id)
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(models.isEmpty)
    }

    private func reasoningPicker(for model: ChatGPTSubscription.Model) -> some View {
        Picker(
            "Reasoning level",
            selection: Binding(
                get: { aiProviderStore.chatGPTReasoningEffort(for: model.id) ?? "" },
                set: { effort in
                    aiProviderStore.updateChatGPTReasoningEffort(
                        effort.isEmpty ? nil : effort,
                        for: model.id
                    )
                }
            )
        ) {
            Text("Model default").tag("")
            ForEach(model.efforts) { effort in
                Text(effort.title).tag(effort.id)
            }
        }
        .pickerStyle(.menu)
    }
}

#Preview {
    let gitManager = GitManager(repositoryPathOverride: "/tmp")
    let providerStore = AIProviderStore()
    let chatGPTSubscription = ChatGPTSubscriptionManager()
    let coordinator = AICommitCoordinator(
        providerStore: providerStore,
        keychainStore: InMemoryAIAPIKeyStore(),
        messageService: AICommitMessageService(chatGPTGenerator: chatGPTSubscription),
        gitManager: gitManager,
        chatGPTSubscription: chatGPTSubscription
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
    .environmentObject(chatGPTSubscription)
    .frame(width: 560, height: 360)
}
