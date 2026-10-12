import XCTest
@testable import AiChat

final class LocalArtifactStoreTests: XCTestCase {
    private var rootURL: URL!
    private var store: LocalArtifactStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatLocalArtifactStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let storage = ModelStorage(modelsDirectoryOverride: rootURL)
        store = LocalArtifactStore(storage: storage)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        store = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    func testGGUFManifestVerificationAndRepairRejectIncompleteArtifact() throws {
        let variant = makeVariant(id: "repair-gguf", format: .gguf)
        let artifactURL = store.artifactURL(for: variant)
        try Data(repeating: 0, count: 1024).write(to: artifactURL)

        try writeManifest(
            LocalArtifactManifest(
                id: variant.id,
                definitionId: variant.definitionId,
                displayName: variant.downloadLabel,
                backend: variant.backend,
                format: variant.artifactFormat,
                relativePath: artifactURL.lastPathComponent,
                sourceURL: variant.downloadSource.urlString,
                fileSizeBytes: 1024,
                isExperimental: false,
                addedAt: Date()
            )
        )

        XCTAssertFalse(store.isVariantDownloaded(variant.id))
        XCTAssertEqual(store.manifests().count, 1)

        store.repairManifests()

        XCTAssertTrue(store.manifests().isEmpty)
        XCTAssertFalse(store.isVariantDownloaded(variant.id))
    }

    func testMLXFinalizationValidatesEveryRequiredFileSize() throws {
        let variant = makeVariant(id: "mlx-size-check", format: .mlx)
        let stagingURL = try store.prepareStagingDirectory(for: variant)

        try writeFile("config.json", bytes: 8, in: stagingURL)
        try writeFile("tokenizer.json", bytes: 6, in: stagingURL)
        try writeFile("model.safetensors", bytes: 10, in: stagingURL)

        XCTAssertThrowsError(
            try store.finalizeMLXDownload(
                stagingDirectory: stagingURL,
                variant: variant,
                expectedFiles: [
                    LocalArtifactExpectedFile(path: "config.json", sizeBytes: 8),
                    LocalArtifactExpectedFile(path: "tokenizer.json", sizeBytes: 6),
                    LocalArtifactExpectedFile(path: "model.safetensors", sizeBytes: 11)
                ]
            )
        )
        XCTAssertFalse(store.isVariantDownloaded(variant.id))

        try store.finalizeMLXDownload(
            stagingDirectory: stagingURL,
            variant: variant,
            expectedFiles: [
                LocalArtifactExpectedFile(path: "config.json", sizeBytes: 8),
                LocalArtifactExpectedFile(path: "tokenizer.json", sizeBytes: 6),
                LocalArtifactExpectedFile(path: "model.safetensors", sizeBytes: 10)
            ]
        )

        XCTAssertTrue(store.isVariantDownloaded(variant.id))
        XCTAssertEqual(store.manifest(for: variant.id)?.fileSizeBytes, 24)
    }

    private func writeManifest(_ manifest: LocalArtifactManifest) throws {
        let manifestDirectory = rootURL.appendingPathComponent("Manifests", isDirectory: true)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestDirectory.appendingPathComponent("\(manifest.id).json"))
    }

    private func writeFile(_ path: String, bytes: Int, in directory: URL) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    private func makeVariant(id: String, format: ModelFormat) -> LocalModelVariant {
        LocalModelVariant(
            id: id,
            definitionId: "definition-\(id)",
            backend: format == .mlx ? .mlx : .llama,
            artifactFormat: format,
            quantization: format == .mlx ? "4-bit" : "Q4_K_M",
            minimumIOSVersion: 18,
            minimumRAMGB: 1,
            preferredDevices: ["Tests"],
            downloadSource: format == .mlx
                ? .huggingFaceRepository(repoID: "example/\(id)")
                : .direct(url: "https://example.com/\(id).gguf"),
            sizeGB: 0.01,
            sizeMB: 10,
            isExperimental: false,
            minimumDeviceDescription: "Tests"
        )
    }
}
