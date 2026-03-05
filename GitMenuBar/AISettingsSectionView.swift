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
                        providerRow(provider)
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

    private func providerRow(_ provider: AIProviderConfig) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.system(size: 11, weight: .semibold))

                Text("\(provider.type.displayName) · \(provider.selectedModel)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if aiProviderStore.preferences.defaultProviderId == provider.id {
                Text("Default")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }

            Button("Edit") {
                editingProvider = provider
                showingProviderEditor = true
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .focusable(false)

            Button("Delete") {
                aiCommitCoordinator.deleteAPIKey(for: provider.id)
                aiProviderStore.deleteProvider(id: provider.id)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundColor(.red)
            .focusable(false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(6)
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

private struct AIProviderEditorSheet: View {
    @EnvironmentObject private var aiCommitCoordinator: AICommitCoordinator
    @Environment(\.dismiss) private var dismiss

    let existingProvider: AIProviderConfig?
    let onSave: (AIProviderConfig, String) -> Void

    @State private var providerName: String
    @State private var providerType: AIProviderType
    @State private var endpointURL: String
    @State private var apiKey: String
    @State private var selectedModel: String
    @State private var availableModels: [String]
    @State private var isTestingConnection = false
    @State private var validationError: String?

    init(existingProvider: AIProviderConfig?, onSave: @escaping (AIProviderConfig, String) -> Void) {
        self.existingProvider = existingProvider
        self.onSave = onSave

        _providerName = State(initialValue: existingProvider?.name ?? "")
        _providerType = State(initialValue: existingProvider?.type ?? .openAI)
        _endpointURL = State(initialValue: existingProvider?.endpointURL ?? AIProviderType.openAI.defaultEndpoint)
        _apiKey = State(initialValue: "")
        _selectedModel = State(initialValue: existingProvider?.selectedModel ?? "")
        _availableModels = State(initialValue: existingProvider?.availableModels ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(existingProvider == nil ? "Add AI Provider" : "Edit AI Provider")
                .font(.headline)

            TextField("Provider name", text: $providerName)
                .textFieldStyle(.roundedBorder)

            Picker("Provider Type", selection: $providerType) {
                ForEach(AIProviderType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            TextField("Endpoint URL", text: $endpointURL)
                .textFieldStyle(.roundedBorder)
                .onChange(of: providerType) { _, type in
                    if endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        endpointURL = type.defaultEndpoint
                    }
                }

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onAppear {
                    if let existingProvider {
                        apiKey = aiCommitCoordinator.apiKey(for: existingProvider.id)
                    }
                }

            HStack {
                Button(isTestingConnection ? "Testing..." : "Test Connection") {
                    Task {
                        await testConnection()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTestingConnection || endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }

            if !availableModels.isEmpty {
                Picker("Model", selection: $selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)
            } else {
                TextField("Model", text: $selectedModel)
                    .textFieldStyle(.roundedBorder)
            }

            if let validationError {
                Text(validationError)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    saveProvider()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 420)
    }

    func testConnection() async {
        validationError = nil
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let models = try await aiCommitCoordinator.testConnectionAndFetchModels(
                providerType: providerType,
                endpointURL: endpointURL,
                apiKey: apiKey
            )

            availableModels = models

            if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let firstModel = models.first
            {
                selectedModel = firstModel
            }
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func saveProvider() {
        validationError = nil

        let trimmedName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            validationError = "Name is required."
            return
        }

        guard !trimmedEndpoint.isEmpty else {
            validationError = "Endpoint URL is required."
            return
        }

        guard !trimmedAPIKey.isEmpty else {
            validationError = "API key is required."
            return
        }

        guard !trimmedModel.isEmpty else {
            validationError = "Model is required."
            return
        }

        let provider = AIProviderConfig(
            id: existingProvider?.id ?? UUID(),
            name: trimmedName,
            type: providerType,
            endpointURL: trimmedEndpoint,
            selectedModel: trimmedModel,
            availableModels: availableModels,
            createdAt: existingProvider?.createdAt ?? Date(),
            updatedAt: Date()
        )

        onSave(provider, trimmedAPIKey)
        dismiss()
    }
}
