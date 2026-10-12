import Foundation

struct LocalRuntimeVariantSelection: Equatable {
    let definition: LocalModelDefinition
    let variant: LocalModelVariant
    let supportState: LocalRuntimeSupportState
}

struct LocalRuntimeVariantSelector {
    let capabilityService: LocalCapabilityService

    init(capabilityService: LocalCapabilityService = LocalCapabilityService()) {
        self.capabilityService = capabilityService
    }

    func bestDownloadedVariant(
        for definition: LocalModelDefinition,
        downloadedVariantIds: Set<String>
    ) -> LocalRuntimeVariantSelection? {
        let ranked = rankedDownloadedVariants(
            for: definition,
            downloadedVariantIds: downloadedVariantIds
        )
        guard let variant = ranked.first else { return nil }
        return LocalRuntimeVariantSelection(
            definition: definition,
            variant: variant,
            supportState: capabilityService.supportState(for: variant)
        )
    }

    func rankedDownloadedVariants(
        for definition: LocalModelDefinition,
        downloadedVariantIds: Set<String>
    ) -> [LocalModelVariant] {
        capabilityService.rank(
            definition.variants.filter { variant in
                downloadedVariantIds.contains(variant.id)
                    && capabilityService.supportState(for: variant).isAvailable
            },
            downloadedVariantIds: downloadedVariantIds
        )
    }

    func bestSupportedVariantToDownload(
        for definition: LocalModelDefinition,
        downloadedVariantIds: Set<String>,
        includeExperimental: Bool
    ) -> LocalModelVariant? {
        capabilityService.rank(
            capabilityService.supportedVariants(
                for: definition,
                includeExperimental: includeExperimental
            ),
            downloadedVariantIds: downloadedVariantIds
        ).first
    }

    func ggufFallbackVariant(
        for definition: LocalModelDefinition,
        downloadedVariantIds: Set<String>,
        excluding failedVariantId: String
    ) -> LocalModelVariant? {
        capabilityService.rank(
            definition.variants.filter { variant in
                variant.id != failedVariantId
                    && variant.backend == .llama
                    && variant.artifactFormat == .gguf
                    && downloadedVariantIds.contains(variant.id)
                    && capabilityService.supportState(for: variant).isAvailable
            },
            downloadedVariantIds: downloadedVariantIds
        ).first
    }
}
