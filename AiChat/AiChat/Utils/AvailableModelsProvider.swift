import Foundation

struct AvailableModelsProvider {
    // Cache to avoid rebuilding model list on every call
    private static var cachedModels: [ModelSelection]?
    private static var lastDownloadedModelIds: Set<String>?

    /// Clear the cache to force rebuild on next call
    @MainActor
    static func invalidateCache() {
        cachedModels = nil
        lastDownloadedModelIds = nil
    }

    @MainActor
    static func getAvailableModels() -> [ProviderModelGroup] {
        var groups: [ProviderModelGroup] = []

        // Add downloaded local models (disabled in Simulator)
        #if !targetEnvironment(simulator)
        let localModels = getDownloadedLocalModels()
        if !localModels.isEmpty {
            groups.append(ProviderModelGroup(
                provider: .local,
                models: localModels
            ))
        }
        #endif

        // Add Apple Foundation Models
        groups.append(ProviderModelGroup(
            provider: .foundationModels,
            models: [ModelInfo(modelId: "foundation-model", displayName: "Apple Foundation")]
        ))

        return groups
    }

    @MainActor
    static func getAllAvailableModels() -> [ModelSelection] {
        // Get currently downloaded model IDs by checking actual files on disk
        // This ensures we always have accurate data, even before ModelDownloadManager fully initializes
        let currentDownloadedModelIds = getActualDownloadedModelIds()

        // Return cached models if downloaded models haven't changed
        if let cached = cachedModels,
           let lastIds = lastDownloadedModelIds,
           currentDownloadedModelIds == lastIds {
            return cached
        }

        // Rebuild model list
        var selections: [ModelSelection] = []

        for group in getAvailableModels() {
            for model in group.models {
                selections.append(ModelSelection(
                    provider: group.provider,
                    model: model
                ))
            }
        }

        // Cache the result
        cachedModels = selections
        lastDownloadedModelIds = currentDownloadedModelIds

        return selections
    }

    /// Get model IDs by checking actual files on disk (not the cached Set)
    /// This ensures accurate results even during app startup before ModelDownloadManager initializes
    private static func getActualDownloadedModelIds() -> Set<String> {
        let downloadManager = ModelDownloadManager.shared
        let definitions = LocalModelRegistry.shared.allDefinitions(includeExperimental: true)
        return Set(definitions.map(\.id).filter { downloadManager.isModelDownloaded($0) })
    }

    @MainActor
    private static func getDownloadedLocalModels() -> [ModelInfo] {
        let downloadManager = ModelDownloadManager.shared
        let definitions = LocalModelRegistry.shared.allDefinitions(includeExperimental: true)

        return definitions.compactMap { definition in
            guard downloadManager.isModelDownloaded(definition.id) else {
                return nil
            }
            let manifests = downloadManager.downloadedArtifacts(for: definition.id)
            let sizeInfo = manifests.first.map { ByteCountFormatter.string(fromByteCount: $0.fileSizeBytes, countStyle: .file) }
                ?? definition.preferredDisplayVariant.formattedSize
            return ModelInfo(
                modelId: definition.id,
                displayName: definition.displayName,
                contextWindow: nil,
                sizeInfo: sizeInfo
            )
        }
    }
}

struct ProviderModelGroup: Identifiable {
    var id: String { provider.rawValue }
    let provider: ProviderID
    let models: [ModelInfo]
}

struct ModelSelection: Identifiable, Hashable {
    var id: String { "\(provider.rawValue)-\(model.modelId)" }
    let provider: ProviderID
    let model: ModelInfo

    var displayName: String {
        // Truncate provider name in the end, not in the middle
        let providerName = truncateProviderName(provider.displayName)

        if let sizeInfo = model.sizeInfo {
            return "\(model.displayName) (\(sizeInfo)) - \(providerName)"
        } else {
            // For Foundation Models, avoid duplication
            if provider == .foundationModels {
                return model.displayName
            }
            return "\(model.displayName) - \(providerName)"
        }
    }

    private func truncateProviderName(_ name: String) -> String {
        // Shorten common provider names
        switch name {
        case "Apple On-device (Foundation Models)":
            return "Apple"
        case "Local (On-Device)":
            return "Local"
        default:
            // For other providers, use first word or truncate if too long
            let maxLength = 15
            if name.count > maxLength {
                return String(name.prefix(maxLength)) + "..."
            }
            return name
        }
    }
}
