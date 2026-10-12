import Foundation

enum SupportedProviderID: Hashable {
    case local
    case foundationModels

    var providerID: ProviderID {
        switch self {
        case .local:
            return .local
        case .foundationModels:
            return .foundationModels
        }
    }
}

enum ProviderID: String, Codable, Identifiable {
    case local
    case foundationModels

    // Legacy persisted values kept for backward compatibility with old chats/settings.
    case openAI
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:
            return "Local"
        case .foundationModels:
            return "Foundation Models"
        case .openAI, .anthropic:
            return "Legacy Cloud Provider"
        }
    }

    var isLegacyAPIProvider: Bool {
        switch self {
        case .openAI, .anthropic:
            return true
        case .local, .foundationModels:
            return false
        }
    }

    var resolvedSupportedProvider: ProviderID {
        supportedProvider.providerID
    }

    var supportedProvider: SupportedProviderID {
        switch self {
        case .local:
            return .local
        case .foundationModels, .openAI, .anthropic:
            return .foundationModels
        }
    }
}

struct ModelInfo: Identifiable, Codable, Hashable {
    var id: String { modelId }
    let modelId: String
    let displayName: String
    let contextWindow: Int?
    let sizeInfo: String?

    init(modelId: String, displayName: String, contextWindow: Int? = nil, sizeInfo: String? = nil) {
        self.modelId = modelId
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.sizeInfo = sizeInfo
    }
}

struct ProviderConfig: Codable {
    var activeProvider: ProviderID
    var localModel: String?
    var foundationModel: String?
    // Legacy field for backward compatibility with earlier Apple Intelligence stub.
    var appleModel: String?
    var temperature: Double
    var maxTokens: Int?

    init(
        activeProvider: ProviderID = .foundationModels,
        localModel: String? = nil,
        foundationModel: String? = nil,
        appleModel: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) {
        self.activeProvider = activeProvider.resolvedSupportedProvider
        self.localModel = localModel
        self.foundationModel = foundationModel ?? appleModel
        self.appleModel = appleModel
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    static var `default`: ProviderConfig { ProviderConfig() }

    func normalized() -> ProviderConfig {
        ProviderConfig(
            activeProvider: activeProvider.resolvedSupportedProvider,
            localModel: localModel,
            foundationModel: foundationModel ?? appleModel,
            appleModel: appleModel,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    /// Get the current model ID for the active provider
    var currentModelId: String? {
        switch activeProvider.supportedProvider {
        case .local:
            return localModel
        case .foundationModels:
            return foundationModel
        }
    }

    /// Update the model for the active provider
    mutating func updateCurrentModel(_ modelId: String?) {
        switch activeProvider.supportedProvider {
        case .local:
            localModel = modelId
        case .foundationModels:
            foundationModel = modelId
        }
    }
}

struct GenerationSettings: Codable, Hashable {
    var temperature: Double
    var maxTokens: Int?
    var model: String?

    init(temperature: Double = 0.7, maxTokens: Int? = nil, model: String? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.model = model
    }
}
