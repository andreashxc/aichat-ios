import Foundation

struct LocalArtifactManifest: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let definitionId: String
    let displayName: String
    let backend: EngineType
    let format: ModelFormat
    let relativePath: String
    let sourceURL: String
    let fileSizeBytes: Int64
    let isExperimental: Bool
    let addedAt: Date
}

struct LocalArtifactExpectedFile: Codable, Hashable, Sendable {
    let path: String
    let sizeBytes: Int64?
}

struct LocalDownloadStagingState: Codable, Hashable, Sendable {
    struct FileState: Codable, Hashable, Sendable {
        let path: String
        let expectedSizeBytes: Int64?
        var downloadedBytes: Int64
        var isComplete: Bool
        var attempts: Int
        var lastError: String?
    }

    let variantId: String
    let definitionId: String
    let sourceURL: String
    let totalBytes: Int64
    var files: [FileState]
    var updatedAt: Date
}

struct LocalArtifactStore {
    private let storage: ModelStorage
    private let fileManager: FileManager

    init(storage: ModelStorage = ModelStorage(), fileManager: FileManager = .default) {
        self.storage = storage
        self.fileManager = fileManager
    }

    var modelsDirectory: URL {
        storage.modelsDirectory
    }

    private var manifestDirectory: URL {
        let url = storage.modelsDirectory.appendingPathComponent("Manifests", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private var stagingDirectory: URL {
        let url = storage.modelsDirectory.appendingPathComponent("Staging", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func manifests() -> [LocalArtifactManifest] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: manifestDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(LocalArtifactManifest.self, from: data)
        }
    }

    func verifiedManifests() -> [LocalArtifactManifest] {
        manifests().filter { manifest in
            verify(manifest: manifest)
        }
    }

    func downloadedDefinitionIds() -> Set<String> {
        Set(verifiedManifests().map(\.definitionId))
    }

    func downloadedVariantIds() -> Set<String> {
        Set(verifiedManifests().map(\.id))
    }

    func manifests(for definitionId: String) -> [LocalArtifactManifest] {
        verifiedManifests().filter { $0.definitionId == definitionId }
    }

    func manifest(for variantId: String) -> LocalArtifactManifest? {
        verifiedManifests().first { $0.id == variantId }
    }

    func isVariantDownloaded(_ variantId: String) -> Bool {
        manifest(for: variantId) != nil
    }

    func isDefinitionDownloaded(_ definitionId: String) -> Bool {
        downloadedDefinitionIds().contains(definitionId)
    }

    func artifactURL(for variant: LocalModelVariant) -> URL {
        switch variant.artifactFormat {
        case .gguf:
            return storage.fileURL(for: variant.id, format: .gguf)
        case .mlx:
            return storage.fileURL(for: variant.id, format: .mlx)
        }
    }

    func stagingURL(for variant: LocalModelVariant) -> URL {
        switch variant.artifactFormat {
        case .gguf:
            return stagingDirectory.appendingPathComponent("\(variant.id).partial.gguf")
        case .mlx:
            return stagingDirectory.appendingPathComponent(variant.id, isDirectory: true)
        }
    }

    func prepareStagingDirectory(for variant: LocalModelVariant) throws -> URL {
        let url = stagingURL(for: variant)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func prepareResumableStagingDirectory(for variant: LocalModelVariant) throws -> URL {
        let url = stagingURL(for: variant)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func removeStagingArtifacts(for variant: LocalModelVariant) {
        try? fileManager.removeItem(at: stagingURL(for: variant))
        try? fileManager.removeItem(at: resumeDataURL(for: variant.id))
        try? fileManager.removeItem(at: stagingStateURL(for: variant.id))
    }

    func resumeDataURL(for variantId: String) -> URL {
        stagingDirectory.appendingPathComponent("\(variantId).resumeData")
    }

    func loadResumeData(for variantId: String) -> Data? {
        try? Data(contentsOf: resumeDataURL(for: variantId))
    }

    func saveResumeData(_ data: Data, for variantId: String) throws {
        try data.write(to: resumeDataURL(for: variantId), options: .atomic)
    }

    func removeResumeData(for variantId: String) {
        try? fileManager.removeItem(at: resumeDataURL(for: variantId))
    }

    func stagingStateURL(for variantId: String) -> URL {
        stagingDirectory.appendingPathComponent("\(variantId).staging.json")
    }

    func loadStagingState(for variantId: String) -> LocalDownloadStagingState? {
        guard let data = try? Data(contentsOf: stagingStateURL(for: variantId)) else {
            return nil
        }
        return try? JSONDecoder().decode(LocalDownloadStagingState.self, from: data)
    }

    func saveStagingState(_ state: LocalDownloadStagingState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: stagingStateURL(for: state.variantId), options: .atomic)
    }

    func removeStagingState(for variantId: String) {
        try? fileManager.removeItem(at: stagingStateURL(for: variantId))
    }

    func finalizeGGUFDownload(tempURL: URL, variant: LocalModelVariant) throws {
        let finalURL = artifactURL(for: variant)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: tempURL, to: finalURL)

        let sizeBytes = fileSize(at: finalURL) ?? 0
        try saveManifest(
            LocalArtifactManifest(
                id: variant.id,
                definitionId: variant.definitionId,
                displayName: variant.downloadLabel,
                backend: variant.backend,
                format: variant.artifactFormat,
                relativePath: finalURL.lastPathComponent,
                sourceURL: variant.downloadSource.urlString,
                fileSizeBytes: sizeBytes,
                isExperimental: variant.isExperimental,
                addedAt: Date()
            )
        )
    }

    func finalizeMLXDownload(
        stagingDirectory: URL,
        variant: LocalModelVariant,
        expectedFiles: [LocalArtifactExpectedFile] = []
    ) throws {
        if let validationError = validateMLXDirectory(at: stagingDirectory, expectedFiles: expectedFiles) {
            throw validationError
        }

        let finalURL = artifactURL(for: variant)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: stagingDirectory, to: finalURL)

        let sizeBytes = directorySize(at: finalURL)
        try saveManifest(
            LocalArtifactManifest(
                id: variant.id,
                definitionId: variant.definitionId,
                displayName: variant.downloadLabel,
                backend: variant.backend,
                format: variant.artifactFormat,
                relativePath: finalURL.lastPathComponent,
                sourceURL: variant.downloadSource.urlString,
                fileSizeBytes: sizeBytes,
                isExperimental: variant.isExperimental,
                addedAt: Date()
            )
        )
        removeStagingState(for: variant.id)
    }

    func deleteVariant(_ variantId: String) throws {
        guard let manifest = manifests().first(where: { $0.id == variantId }) else {
            return
        }

        let artifactURL = storage.modelsDirectory.appendingPathComponent(manifest.relativePath)
        if fileManager.fileExists(atPath: artifactURL.path) {
            try fileManager.removeItem(at: artifactURL)
        }

        let manifestURL = manifestDirectory.appendingPathComponent("\(variantId).json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }
    }

    func deleteDefinition(_ definitionId: String) throws {
        for manifest in manifests().filter({ $0.definitionId == definitionId }) {
            try deleteVariant(manifest.id)
        }
    }

    func repairManifests() {
        for manifest in manifests() where !verify(manifest: manifest) {
            let manifestURL = manifestDirectory.appendingPathComponent("\(manifest.id).json")
            try? fileManager.removeItem(at: manifestURL)
        }
    }

    private func saveManifest(_ manifest: LocalArtifactManifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestDirectory.appendingPathComponent("\(manifest.id).json"), options: .atomic)
    }

    func verify(manifest: LocalArtifactManifest) -> Bool {
        let artifactURL = storage.modelsDirectory.appendingPathComponent(manifest.relativePath)
        switch manifest.format {
        case .gguf:
            guard let size = fileSize(at: artifactURL) else { return false }
            return size > 10 * 1024 * 1024 && size == manifest.fileSizeBytes
        case .mlx:
            return storage.isMLXModelComplete(modelId: manifest.id)
                && directorySize(at: artifactURL) == manifest.fileSizeBytes
        }
    }

    func validateMLXDirectory(
        at url: URL,
        expectedFiles: [LocalArtifactExpectedFile] = []
    ) -> DownloadError? {
        let configURL = url.appendingPathComponent("config.json")
        if !fileManager.fileExists(atPath: configURL.path) {
            return .repositoryManifestFailed("Repository is missing config.json.")
        }

        let tokenizerModelURL = url.appendingPathComponent("tokenizer.model")
        let tokenizerJSONURL = url.appendingPathComponent("tokenizer.json")
        if !fileManager.fileExists(atPath: tokenizerModelURL.path),
           !fileManager.fileExists(atPath: tokenizerJSONURL.path) {
            return .repositoryManifestFailed("Repository is missing tokenizer files.")
        }

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return .incompleteDownload("Downloaded MLX files could not be inspected.")
        }

        var hasWeights = false
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "safetensors" {
            hasWeights = true
            break
        }

        if !hasWeights {
            return .repositoryManifestFailed("Repository does not contain any .safetensors weights.")
        }

        for file in expectedFiles {
            let fileURL = url.appendingPathComponent(file.path)
            guard let size = fileSize(at: fileURL) else {
                return .incompleteDownload("Missing required file \(file.path).")
            }
            if let expectedSize = file.sizeBytes, size != expectedSize {
                return .incompleteDownload("\(file.path) expected \(expectedSize) bytes, got \(size) bytes.")
            }
            if size == 0 {
                return .incompleteDownload("\(file.path) is empty.")
            }
        }

        return nil
    }

    func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    func directorySize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
}
