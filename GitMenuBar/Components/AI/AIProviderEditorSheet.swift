import SwiftUI

struct AIProviderEditorSheet: View {
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

            let shouldSelectFirstModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if shouldSelectFirstModel, let firstModel = models.first {
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

#Preview("AI Provider Editor") {
    let gitManager = GitManager(repositoryPathOverride: "/tmp")
    let providerStore = AIProviderStore()
    let keychainStore = InMemoryAIAPIKeyStore()
    let coordinator = AICommitCoordinator(
        providerStore: providerStore,
        keychainStore: keychainStore,
        messageService: AICommitMessageService(),
        gitManager: gitManager
    )

    return AIProviderEditorSheet(existingProvider: nil, onSave: { _, _ in })
        .environmentObject(coordinator)
}
