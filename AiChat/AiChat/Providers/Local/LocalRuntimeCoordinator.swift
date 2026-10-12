import Foundation

actor LocalRuntimeCoordinator {
    private let registry = LocalModelRegistry.shared
    private let capabilityService = LocalCapabilityService()
    private let variantSelector: LocalRuntimeVariantSelector
    private let artifactStore = LocalArtifactStore()
    private let modelStorage = ModelStorage()
    private let hybridProvider = HybridLocalProvider()

    private var lastLoadedVariantId: String?
    private var runtimeStatus: LocalRuntimeStatus = .idle

    init() {
        self.variantSelector = LocalRuntimeVariantSelector(capabilityService: capabilityService)
    }

    func generate(
        request: ChatRequest,
        definitionId: String,
        onToken: @escaping (String) -> Void
    ) async throws {
        let profile = LocalGenerationProfile.from(request: request)
        let definition = try resolveDefinition(definitionId)
        let selection = try resolveSelection(for: definition)
        let renderer = LocalPromptRendererFactory.makeRenderer(for: definition)

        let variant = try await ensureVariantLoaded(
            selection.variant,
            definition: definition,
            supportState: selection.supportState,
            reason: "initial selection"
        )

        do {
            _ = try await generateWithLoadedVariant(
                variant,
                request: request,
                renderer: renderer,
                profile: profile,
                onToken: onToken
            )
        } catch {
            guard let fallback = fallbackVariant(
                for: definition,
                failedVariant: variant,
                error: error
            ) else {
                updateErrorStatus(
                    modelId: variant.id,
                    backend: variant.backend,
                    error: error
                )
                throw error
            }

            logFallback(
                definition: definition,
                from: variant,
                to: fallback,
                reason: "generation failed: \(error.localizedDescription)"
            )

            let loadedFallback = try await ensureVariantLoaded(
                fallback,
                definition: definition,
                supportState: capabilityService.supportState(for: fallback),
                reason: "generation fallback after \(variant.backend.displayName) failure"
            )

            do {
                _ = try await generateWithLoadedVariant(
                    loadedFallback,
                    request: request,
                    renderer: renderer,
                    profile: profile,
                    onToken: onToken
                )
            } catch {
                updateErrorStatus(
                    modelId: loadedFallback.id,
                    backend: loadedFallback.backend,
                    error: error
                )
                throw error
            }
        }
    }

    func preload(definitionId: String) async throws {
        let definition = try resolveDefinition(definitionId)
        let selection = try resolveSelection(for: definition)
        _ = try await ensureVariantLoaded(
            selection.variant,
            definition: definition,
            supportState: selection.supportState,
            reason: "preload"
        )
    }

    func cleanup() async {
        await hybridProvider.cleanup()
        lastLoadedVariantId = nil
        runtimeStatus = .idle
    }

    func currentStatus() -> LocalRuntimeStatus {
        runtimeStatus
    }

    func availableDownloadedDefinitions() -> [LocalModelDefinition] {
        let downloadedIds = artifactStore.downloadedDefinitionIds()
        return registry.allDefinitions(includeExperimental: true)
            .filter { downloadedIds.contains($0.id) }
    }

    func runtimeSummary(for definitionId: String) -> String {
        guard let definition = registry.definition(for: definitionId, includeExperimental: true) else {
            return "Unknown local model"
        }

        let downloadedVariantIds = artifactStore.downloadedVariantIds()
        let downloadedSupported = variantSelector.rankedDownloadedVariants(
            for: definition,
            downloadedVariantIds: downloadedVariantIds
        )
        let variants = downloadedSupported.isEmpty
            ? [variantSelector.bestSupportedVariantToDownload(
                for: definition,
                downloadedVariantIds: downloadedVariantIds,
                includeExperimental: ModelPreferences.localIncludeExperimental
            )].compactMap { $0 }
            : downloadedSupported

        guard let best = variants.first else {
            return "No compatible runtime on this device"
        }

        let supportState = capabilityService.supportState(for: best)
        if let warning = supportState.warning {
            return "\(best.backend.displayName) • \(best.formattedSize) • \(warning)"
        }

        return "\(best.backend.displayName) • \(best.formattedSize)"
    }

    private func resolveSelection(for definition: LocalModelDefinition) throws -> LocalRuntimeVariantSelection {
        let downloadedVariantIds = artifactStore.downloadedVariantIds()
        if let selection = variantSelector.bestDownloadedVariant(
            for: definition,
            downloadedVariantIds: downloadedVariantIds
        ) {
            logSelection(
                definition: definition,
                variant: selection.variant,
                supportState: selection.supportState,
                reason: "best downloaded compatible variant"
            )
            return selection
        }

        if let variant = variantSelector.bestSupportedVariantToDownload(
            for: definition,
            downloadedVariantIds: downloadedVariantIds,
            includeExperimental: ModelPreferences.localIncludeExperimental
        ) {
            throw LocalProviderError.modelNotDownloaded(modelId: definition.id, suggestion: variant.downloadLabel)
        }

        if let firstVariant = definition.variants.first,
           case .unsupported(let reason) = capabilityService.supportState(for: firstVariant) {
            throw LocalProviderError.unsupportedModelArchitecture(
                modelId: definition.id,
                details: reason
            )
        }

        throw LocalProviderError.unsupportedModelArchitecture(
            modelId: definition.id,
            details: "No compatible variant is available for this device."
        )
    }

    private func resolveDefinition(_ definitionId: String) throws -> LocalModelDefinition {
        guard let definition = registry.definition(
            for: definitionId,
            includeExperimental: true
        ) else {
            throw LocalProviderError.unsupportedModelArchitecture(
                modelId: definitionId,
                details: "Model is not present in the local registry."
            )
        }
        return definition
    }

    private func ensureVariantLoaded(
        _ variant: LocalModelVariant,
        definition: LocalModelDefinition,
        supportState: LocalRuntimeSupportState,
        reason: String
    ) async throws -> LocalModelVariant {
        if lastLoadedVariantId == variant.id {
            runtimeStatus = LocalRuntimeStatus(
                phase: .loaded,
                currentModelId: variant.id,
                backend: variant.backend,
                tokensPerSecond: runtimeStatus.tokensPerSecond,
                message: runtimeStatus.message
            )
            return variant
        }

        let warning = try preflightLoadWarning(for: variant, supportState: supportState)
        logSelection(
            definition: definition,
            variant: variant,
            supportState: supportState,
            reason: reason,
            memoryWarning: warning
        )

        runtimeStatus = LocalRuntimeStatus(
            phase: .loading,
            currentModelId: variant.id,
            backend: variant.backend,
            tokensPerSecond: nil,
            message: warning
        )

        do {
            try await hybridProvider.loadVariant(variant)
            lastLoadedVariantId = variant.id
            runtimeStatus = LocalRuntimeStatus(
                phase: .loaded,
                currentModelId: variant.id,
                backend: variant.backend,
                tokensPerSecond: nil,
                message: warning
            )
            return variant
        } catch {
            guard let fallback = fallbackVariant(
                for: definition,
                failedVariant: variant,
                error: error
            ) else {
                updateErrorStatus(
                    modelId: variant.id,
                    backend: variant.backend,
                    error: error
                )
                throw error
            }

            logFallback(
                definition: definition,
                from: variant,
                to: fallback,
                reason: "load failed: \(error.localizedDescription)"
            )

            return try await ensureVariantLoaded(
                fallback,
                definition: definition,
                supportState: capabilityService.supportState(for: fallback),
                reason: "load fallback after \(variant.backend.displayName) failure"
            )
        }
    }

    private func generateWithLoadedVariant(
        _ variant: LocalModelVariant,
        request: ChatRequest,
        renderer: LocalPromptRenderer,
        profile: LocalGenerationProfile,
        onToken: @escaping (String) -> Void
    ) async throws -> Double? {
        var tokenCount = 0
        let startedAt = Date()

        runtimeStatus = LocalRuntimeStatus(
            phase: .generating,
            currentModelId: variant.id,
            backend: variant.backend,
            tokensPerSecond: nil,
            message: nil
        )

        let backend: LocalPromptBackend = variant.backend == .mlx ? .mlx : .swiftLlama
        let prompt = renderer.render(request: request, profile: profile, backend: backend)

        try await hybridProvider.generate(prompt: prompt) { token in
            tokenCount += 1
            onToken(token)
        }

        let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
        let tokensPerSecond = tokenCount > 0 ? Double(tokenCount) / elapsed : nil

        runtimeStatus = LocalRuntimeStatus(
            phase: .loaded,
            currentModelId: variant.id,
            backend: variant.backend,
            tokensPerSecond: tokensPerSecond,
            message: nil
        )

        return tokensPerSecond
    }

    private func fallbackVariant(
        for definition: LocalModelDefinition,
        failedVariant: LocalModelVariant,
        error: Error
    ) -> LocalModelVariant? {
        guard failedVariant.backend == .mlx, isRuntimeRecoverable(error) else {
            return nil
        }

        return variantSelector.ggufFallbackVariant(
            for: definition,
            downloadedVariantIds: artifactStore.downloadedVariantIds(),
            excluding: failedVariant.id
        )
    }

    private func isRuntimeRecoverable(_ error: Error) -> Bool {
        if case InferenceEngineError.outOfMemory = error {
            return true
        }

        let description = error.localizedDescription.lowercased()
        let recoverableFragments = [
            "memory",
            "out of memory",
            "allocation",
            "resource",
            "runtime",
            "metal",
            "gpu",
            "mlx",
            "failed to load",
            "generation failed"
        ]

        return recoverableFragments.contains { description.contains($0) }
    }

    private func preflightLoadWarning(
        for variant: LocalModelVariant,
        supportState: LocalRuntimeSupportState
    ) throws -> String? {
        let profile = DeviceCapabilities.currentProfile()
        let actualSizeBytes = modelStorage.getModelSize(modelId: variant.id)
            ?? Int64(variant.sizeGB * 1_073_741_824)
        let actualSizeGB = Double(actualSizeBytes) / 1_073_741_824.0
        var warnings = [String]()

        if let warning = supportState.warning {
            warnings.append(warning)
        }

        if actualSizeGB > profile.maxRecommendedModelSizeGB {
            warnings.append(
                "Model size \(String(format: "%.2f", actualSizeGB))GB exceeds the recommended \(String(format: "%.2f", profile.maxRecommendedModelSizeGB))GB budget."
            )
        }

        if actualSizeBytes > Int64(profile.physicalMemoryBytes) {
            throw LocalProviderError.unsupportedModelArchitecture(
                modelId: variant.definitionId,
                details: "Variant \(variant.id) is larger than physical memory on this device."
            )
        }

        if let freeSpaceBytes = availableDiskSpaceBytes() {
            let freeSpaceMB = Double(freeSpaceBytes) / 1_048_576.0
            if freeSpaceBytes < 64 * 1_048_576 {
                throw LocalProviderError.inferenceError(
                    "Only \(String(format: "%.0f", freeSpaceMB))MB disk space is available. Free at least 64MB before loading local models."
                )
            }

            let scratchWarningThreshold = max(256 * 1_048_576, actualSizeBytes / 10)
            if freeSpaceBytes < scratchWarningThreshold {
                warnings.append(
                    "Low disk space may make local runtime caches unstable (\(String(format: "%.0f", freeSpaceMB))MB free)."
                )
            }
        }

        let warning = warnings.isEmpty ? nil : warnings.joined(separator: " ")
        if let warning {
            Logger.shared.info("⚠️ Local runtime preflight warning for \(variant.id): \(warning)")
        }
        return warning
    }

    private func availableDiskSpaceBytes() -> Int64? {
        let values = try? modelStorage.modelsDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func logSelection(
        definition: LocalModelDefinition,
        variant: LocalModelVariant,
        supportState: LocalRuntimeSupportState,
        reason: String,
        memoryWarning: String? = nil
    ) {
        let warning = memoryWarning ?? supportState.warning ?? "none"
        Logger.shared.info("""
        Local runtime selection:
        - selected definition: \(definition.id) (\(definition.displayName))
        - selected variant: \(variant.id)
        - backend: \(variant.backend.displayName)
        - reason: \(reason)
        - memory warning: \(warning)
        """)
    }

    private func logFallback(
        definition: LocalModelDefinition,
        from failedVariant: LocalModelVariant,
        to fallbackVariant: LocalModelVariant,
        reason: String
    ) {
        Logger.shared.info("""
        Local runtime fallback:
        - selected definition: \(definition.id) (\(definition.displayName))
        - failed variant: \(failedVariant.id)
        - fallback variant: \(fallbackVariant.id)
        - backend: \(fallbackVariant.backend.displayName)
        - reason for fallback: \(reason)
        - memory warning: \(capabilityService.supportState(for: fallbackVariant).warning ?? "none")
        """)
    }

    private func updateErrorStatus(
        modelId: String,
        backend: EngineType,
        error: Error
    ) {
        runtimeStatus = LocalRuntimeStatus(
            phase: .error,
            currentModelId: modelId,
            backend: backend,
            tokensPerSecond: nil,
            message: error.localizedDescription
        )
    }
}
