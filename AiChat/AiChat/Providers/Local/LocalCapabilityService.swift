import Foundation

enum LocalRuntimeSupportState: Equatable {
    case supported
    case supportedWithWarning(String)
    case unsupported(String)

    var reason: String? {
        switch self {
        case .supported:
            return nil
        case .supportedWithWarning(let reason):
            return reason
        case .unsupported(let reason):
            return reason
        }
    }

    var warning: String? {
        switch self {
        case .supported:
            return nil
        case .supportedWithWarning(let reason):
            return reason
        case .unsupported:
            return nil
        }
    }

    var isAvailable: Bool {
        switch self {
        case .supported:
            return true
        case .supportedWithWarning:
            return true
        case .unsupported:
            return false
        }
    }
}

struct LocalCapabilityService {
    private let profile: DeviceCapabilityProfile

    init(profile: DeviceCapabilityProfile = DeviceCapabilities.currentProfile()) {
        self.profile = profile
    }

    func supportState(for variant: LocalModelVariant) -> LocalRuntimeSupportState {
        if profile.isSimulator {
            return .unsupported("Local models run only on a real iPhone or iPad.")
        }

        if let runtimeRestriction = runtimeCompatibilityRestriction(for: variant) {
            return runtimeRestriction
        }

        if !isCurrentOSCompatible(with: variant) {
            return .unsupported("Requires iOS \(String(format: "%.1f", variant.minimumIOSVersion)) or newer.")
        }

        if !profile.meetsMinimumRAMGB(variant.minimumRAMGB) {
            let requiredMB = DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: variant.minimumRAMGB)
            return .unsupported("Requires at least \(requiredMB) MB physical memory.")
        }

        if variant.backend == .mlx && !profile.supportsMLX {
            return .unsupported("MLX is unavailable on this device.")
        }

        if !supports(engine: variant.backend) {
            return .unsupported("\(variant.backend.displayName) is unavailable on this device.")
        }

        if variant.sizeGB > profile.maxRecommendedModelSizeGB {
            return .supportedWithWarning("Model exceeds the recommended memory budget for this device. Download may work, but loading can be unstable.")
        }

        return .supported
    }

    func supportedVariants(
        for definition: LocalModelDefinition,
        includeExperimental: Bool
    ) -> [LocalModelVariant] {
        definition.variants.filter { variant in
            (includeExperimental || !variant.isExperimental) && supportState(for: variant).isAvailable
        }
    }

    func rank(
        _ variants: [LocalModelVariant],
        downloadedVariantIds: Set<String>
    ) -> [LocalModelVariant] {
        variants.sorted { lhs, rhs in
            score(lhs, downloadedVariantIds: downloadedVariantIds) > score(rhs, downloadedVariantIds: downloadedVariantIds)
        }
    }

    func preferredDownloadVariant(
        for definition: LocalModelDefinition,
        includeExperimental: Bool
    ) -> LocalModelVariant? {
        let candidates = supportedVariants(for: definition, includeExperimental: includeExperimental)
        return rank(candidates, downloadedVariantIds: []).first
    }

    private func score(_ variant: LocalModelVariant, downloadedVariantIds: Set<String>) -> Int {
        var score = 0

        if downloadedVariantIds.contains(variant.id) {
            score += 1000
        }
        if !variant.isExperimental {
            score += 500
        }

        if case .supportedWithWarning = supportState(for: variant) {
            score -= 120
        }

        switch ModelPreferences.localBackendPreference {
        case .auto:
            if profile.recommendedBackend == variant.backend {
                score += 120
            }
        case .gguf:
            if variant.backend == .llama {
                score += 180
            }
        case .mlx:
            if variant.backend == .mlx {
                score += 180
            }
        }

        if profile.isIPad, variant.minimumDeviceDescription.lowercased().contains("ipad") {
            score += 25
        }

        if !profile.isIPad, variant.minimumDeviceDescription.lowercased().contains("iphone") {
            score += 25
        }

        score += max(0, 100 - Int(variant.sizeGB * 10))
        return score
    }

    private func isCurrentOSCompatible(with variant: LocalModelVariant) -> Bool {
        profile.supportsIOSVersion(variant.minimumIOSVersion)
    }

    private func supports(engine: EngineType) -> Bool {
        switch engine {
        case .mlx:
            return profile.supportsMLX
        case .llama:
            return profile.supportsIOSVersion(engine.minimumIOSVersion) && !profile.isSimulator
        }
    }

    private func runtimeCompatibilityRestriction(for variant: LocalModelVariant) -> LocalRuntimeSupportState? {
        let variantID = variant.id.lowercased()

        if variant.backend == .llama,
           (variantID.hasPrefix("qwen3-") || variantID.hasPrefix("qwen3.")) {
            return .unsupported("Qwen 3 GGUF is not supported by the bundled llama runtime yet. Use an MLX variant instead.")
        }

        if variant.backend == .llama, variantID.hasPrefix("gemma-3") {
            return .unsupported("Gemma 3 is currently exposed only through MLX on this build.")
        }

        return nil
    }
}
