import Foundation

enum LocalModelCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case text
    case thinking
    case toolCallReady = "tool-call-ready"
    case vision
}

enum LocalModelTag: String, Codable, Hashable, Sendable {
    case recommended
    case experimental
    case new
    case vision
    case highCPU = "high-cpu"
}

enum LocalModelFamilyCategory: String, Codable, Hashable, Sendable {
    case featured = "Featured"
    case experimental = "Experimental"
    case legacy = "Legacy"
}

enum LocalDownloadSource: Hashable, Codable, Sendable {
    case direct(url: String)
    case huggingFaceRepository(repoID: String)

    var urlString: String {
        switch self {
        case .direct(let url):
            return url
        case .huggingFaceRepository(let repoID):
            return "https://huggingface.co/\(repoID)"
        }
    }
}

struct LocalModelVariant: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let definitionId: String
    let backend: EngineType
    let artifactFormat: ModelFormat
    let quantization: String
    let minimumIOSVersion: Double
    let minimumRAMGB: Int
    let preferredDevices: [String]
    let downloadSource: LocalDownloadSource
    let sizeGB: Double
    let sizeMB: Int
    let isExperimental: Bool
    let minimumDeviceDescription: String

    var formattedSize: String {
        if sizeGB >= 1.0 {
            return String(format: "%.2f GB", sizeGB)
        } else {
            return "\(sizeMB) MB"
        }
    }

    var backendLabel: String {
        "\(backend.displayName) • \(artifactFormat.rawValue)"
    }

    var downloadLabel: String {
        "\(backend.displayName) \(quantization)"
    }
}

struct LocalModelDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let familyId: String
    let familyName: String
    let icon: String
    let displayName: String
    let description: String
    let tags: [LocalModelTag]
    let capabilities: Set<LocalModelCapability>
    let highlights: [String]
    let variants: [LocalModelVariant]

    var stableVariants: [LocalModelVariant] {
        variants.filter { !$0.isExperimental }
    }

    var experimentalVariants: [LocalModelVariant] {
        variants.filter(\.isExperimental)
    }

    var formattedCapabilities: String {
        highlights.joined(separator: ", ")
    }

    var preferredDisplayVariant: LocalModelVariant {
        stableVariants.first ?? variants[0]
    }
}

struct LocalModelFamily: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let icon: String
    let definitions: [LocalModelDefinition]
    let category: LocalModelFamilyCategory
}

final class LocalModelRegistry: @unchecked Sendable {
    static let shared = LocalModelRegistry()

    private init() {}

    func families(includeExperimental: Bool = true) -> [LocalModelFamily] {
        let catalog = baseCatalog()
        let filtered = catalog.compactMap { family -> LocalModelFamily? in
            let definitions = family.definitions.compactMap { definition -> LocalModelDefinition? in
                let variants = includeExperimental
                    ? definition.variants
                    : definition.variants.filter { !$0.isExperimental }
                guard !variants.isEmpty else { return nil }
                return LocalModelDefinition(
                    id: definition.id,
                    familyId: definition.familyId,
                    familyName: definition.familyName,
                    icon: definition.icon,
                    displayName: definition.displayName,
                    description: definition.description,
                    tags: definition.tags.filter { includeExperimental || $0 != .experimental },
                    capabilities: definition.capabilities,
                    highlights: definition.highlights,
                    variants: variants
                )
            }

            guard !definitions.isEmpty else { return nil }
            return LocalModelFamily(
                id: family.id,
                name: family.name,
                icon: family.icon,
                definitions: adaptDefinitionsForCurrentDevice(definitions),
                category: family.category
            )
        }

        return filtered.compactMap { family in
            guard !family.definitions.isEmpty else { return nil }
            return family
        }
    }

    func allDefinitions(includeExperimental: Bool = true) -> [LocalModelDefinition] {
        families(includeExperimental: includeExperimental).flatMap(\.definitions)
    }

    func definition(for id: String, includeExperimental: Bool = true) -> LocalModelDefinition? {
        allDefinitions(includeExperimental: includeExperimental).first { $0.id == id }
    }

    func variant(for id: String, includeExperimental: Bool = true) -> LocalModelVariant? {
        allDefinitions(includeExperimental: includeExperimental)
            .flatMap(\.variants)
            .first { $0.id == id }
    }

    private func adaptDefinitionsForCurrentDevice(_ definitions: [LocalModelDefinition]) -> [LocalModelDefinition] {
        if DeviceCapabilities.isIPad() {
            return definitions.map { definition in
                let ipadFirst = definition.variants.sorted {
                    scoreForCurrentDevice($0) > scoreForCurrentDevice($1)
                }
                return LocalModelDefinition(
                    id: definition.id,
                    familyId: definition.familyId,
                    familyName: definition.familyName,
                    icon: definition.icon,
                    displayName: definition.displayName,
                    description: definition.description,
                    tags: definition.tags,
                    capabilities: definition.capabilities,
                    highlights: definition.highlights,
                    variants: ipadFirst
                )
            }
        }

        return definitions
            .filter { definition in
                definition.variants.contains { !$0.minimumDeviceDescription.lowercased().contains("ipad only") }
            }
            .map { definition in
                let filtered = definition.variants.filter {
                    !$0.minimumDeviceDescription.lowercased().contains("ipad only")
                }
                return LocalModelDefinition(
                    id: definition.id,
                    familyId: definition.familyId,
                    familyName: definition.familyName,
                    icon: definition.icon,
                    displayName: definition.displayName,
                    description: definition.description,
                    tags: definition.tags,
                    capabilities: definition.capabilities,
                    highlights: definition.highlights,
                    variants: filtered.isEmpty ? definition.variants : filtered
                )
            }
    }

    private func scoreForCurrentDevice(_ variant: LocalModelVariant) -> Int {
        let description = variant.minimumDeviceDescription.lowercased()
        if DeviceCapabilities.isIPad() {
            return description.contains("ipad") ? 2 : 1
        }
        return description.contains("iphone") ? 2 : 1
    }

    private func ggufVariant(
        id: String,
        definitionId: String,
        url: String,
        sizeGB: Double,
        sizeMB: Int,
        minimumRAMGB: Int,
        minimumDeviceDescription: String,
        isExperimental: Bool = false
    ) -> LocalModelVariant {
        LocalModelVariant(
            id: id,
            definitionId: definitionId,
            backend: .llama,
            artifactFormat: .gguf,
            quantization: "Q4_K_M",
            minimumIOSVersion: EngineType.llama.minimumIOSVersion,
            minimumRAMGB: minimumRAMGB,
            preferredDevices: [minimumDeviceDescription],
            downloadSource: .direct(url: url),
            sizeGB: sizeGB,
            sizeMB: sizeMB,
            isExperimental: isExperimental,
            minimumDeviceDescription: minimumDeviceDescription
        )
    }

    private func mlxVariant(
        id: String,
        definitionId: String,
        repoID: String,
        sizeGB: Double,
        sizeMB: Int,
        minimumRAMGB: Int,
        minimumDeviceDescription: String,
        isExperimental: Bool = false
    ) -> LocalModelVariant {
        LocalModelVariant(
            id: id,
            definitionId: definitionId,
            backend: .mlx,
            artifactFormat: .mlx,
            quantization: "4-bit",
            minimumIOSVersion: EngineType.mlx.minimumIOSVersion,
            minimumRAMGB: minimumRAMGB,
            preferredDevices: [minimumDeviceDescription],
            downloadSource: .huggingFaceRepository(repoID: repoID),
            sizeGB: sizeGB,
            sizeMB: sizeMB,
            isExperimental: isExperimental,
            minimumDeviceDescription: minimumDeviceDescription
        )
    }

    // Public release catalog: only verified Apache-2.0 Qwen 3 downloads.
    // See MODEL_PERMISSIONS.md for excluded variants and model obligations.
    private func baseCatalog() -> [LocalModelFamily] {
        [
            LocalModelFamily(
                id: "qwen-3",
                name: "Qwen 3",
                icon: "⚡",
                definitions: [
                    LocalModelDefinition(
                        id: "qwen3-1.7b",
                        familyId: "qwen-3",
                        familyName: "Qwen 3",
                        icon: "⚡",
                        displayName: "Qwen 3 (1.7B MLX)",
                        description: "Primary modern Qwen target for real iPhone and iPad devices with MLX support.",
                        tags: [.recommended],
                        capabilities: [.text, .thinking, .toolCallReady],
                        highlights: ["reasoning", "coding", "multilingual"],
                        variants: [
                            mlxVariant(
                                id: "qwen3-1.7b-mlx",
                                definitionId: "qwen3-1.7b",
                                repoID: "mlx-community/Qwen3-1.7B-4bit",
                                sizeGB: 0.95,
                                sizeMB: 968,
                                minimumRAMGB: 8,
                                minimumDeviceDescription: "iOS 18 real device, 7,500 MB+ memory"
                            )
                        ]
                    ),
                    LocalModelDefinition(
                        id: "qwen3-4b",
                        familyId: "qwen-3",
                        familyName: "Qwen 3",
                        icon: "⚡",
                        displayName: "Qwen 3 (4B MLX)",
                        description: "Higher quality MLX Qwen build for iPad-first usage and newer Pro iPhones.",
                        tags: [.experimental, .highCPU],
                        capabilities: [.text, .thinking, .toolCallReady],
                        highlights: ["higher-quality", "coding", "reasoning"],
                        variants: [
                            mlxVariant(
                                id: "qwen3-4b-mlx",
                                definitionId: "qwen3-4b",
                                repoID: "mlx-community/Qwen3-4B-4bit",
                                sizeGB: 2.15,
                                sizeMB: 2201,
                                minimumRAMGB: 8,
                                minimumDeviceDescription: "iOS 18 real device, 7,500 MB+ memory",
                                isExperimental: true
                            )
                        ]
                    )
                ],
                category: .featured
            )
        ]
    }

}

final class LocalModelCatalog: @unchecked Sendable {
    static let shared = LocalModelCatalog()

    private let registry = LocalModelRegistry.shared

    private init() {}

    func families(includeExperimental: Bool = true) -> [LocalModelFamily] {
        registry.families(includeExperimental: includeExperimental)
    }

    func definitions(includeExperimental: Bool = true) -> [LocalModelDefinition] {
        registry.allDefinitions(includeExperimental: includeExperimental)
    }

    func getModelById(_ id: String) -> LocalModelDefinition? {
        registry.definition(for: id)
    }
}
