import Foundation

@MainActor
protocol LocalProviding: AnyObject {
    var id: ProviderID { get }
    var displayName: String { get }
    func generate(request: ChatRequest) async throws -> String
    func generateStreaming(
        request: ChatRequest,
        onToken: @escaping (String) -> Void
    ) async throws
    func supportsModels() -> Bool
    func availableModels() async -> [ModelInfo]
    func loadModel(modelName: String) async throws
    func cleanup() async
    var providerStatus: String { get async }
    var runtimeStatus: LocalRuntimeStatus { get async }
}

@MainActor
final class LocalProvider: LocalProviding, LLMProvider {
    var id: ProviderID { .local }
    var displayName: String { "Local" }

    private let runtimeCoordinator = LocalRuntimeCoordinator()

    func generate(request: ChatRequest) async throws -> String {
        var response = ""
        try await generateStreaming(request: request) { token in
            response += token
        }
        return LocalResponseSanitizer.clean(response)
    }

    /// Generate response with streaming support
    func generateStreaming(
        request: ChatRequest,
        onToken: @escaping (String) -> Void
    ) async throws {
        Logger.shared.info("LocalProvider: Starting streaming generation")

        let modelId: String
        if let selectedModel = request.settings.model {
            modelId = selectedModel
        } else if let defaultModel = await getDefaultModel() {
            modelId = defaultModel
        } else {
            throw LocalProviderError.noModelSelected
        }

        Logger.shared.info("LocalProvider: Using model: \(modelId)")
        try await runtimeCoordinator.generate(request: request, definitionId: modelId, onToken: onToken)

        Logger.shared.info("LocalProvider: Generation complete")
    }

    func supportsModels() -> Bool { true }

    func availableModels() async -> [ModelInfo] {
        let definitions = await runtimeCoordinator.availableDownloadedDefinitions()
        return definitions.map { definition in
            ModelInfo(
                modelId: definition.id,
                displayName: definition.displayName,
                contextWindow: 2048
            )
        }
    }

    private func getDefaultModel() async -> String? {
        (await runtimeCoordinator.availableDownloadedDefinitions()).first?.id
    }

    /// Preload model to avoid UI lag
    func loadModel(modelName: String) async throws {
        try await runtimeCoordinator.preload(definitionId: modelName)
    }

    /// Clean up resources
    func cleanup() async {
        await runtimeCoordinator.cleanup()
    }

    /// Получить статус provider
    var providerStatus: String {
        get async {
            if let model = await getDefaultModel() {
                return await runtimeCoordinator.runtimeSummary(for: model)
            }
            return "No local model downloaded"
        }
    }

    var runtimeStatus: LocalRuntimeStatus {
        get async {
            await runtimeCoordinator.currentStatus()
        }
    }
}

enum LocalProviderError: Error, LocalizedError {
    case noModelSelected
    case modelNotDownloaded(modelId: String, suggestion: String? = nil)
    case unsupportedModelArchitecture(modelId: String, details: String)
    case inferenceError(String)

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No local model selected. Please select a model in Settings."
        case .modelNotDownloaded(let modelId, let suggestion):
            if let suggestion {
                return "Model '\(modelId)' is not downloaded. Download a compatible variant first (\(suggestion))."
            }
            return "Model '\(modelId)' is not downloaded. Please download it from Settings > Manage Models."
        case .unsupportedModelArchitecture(let modelId, let details):
            return "Model '\(modelId)' is not supported: \(details)"
        case .inferenceError(let reason):
            return "Inference failed: \(reason)"
        }
    }
}
