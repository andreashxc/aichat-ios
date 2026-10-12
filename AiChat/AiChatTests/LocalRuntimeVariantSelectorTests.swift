import XCTest
@testable import AiChat

final class LocalRuntimeVariantSelectorTests: XCTestCase {
    func testBestDownloadedVariantPrefersMLXWhenWithinBudgetOnMLXDevice() {
        let profile = fakeProfile(memoryMB: 7_700)
        let selector = LocalRuntimeVariantSelector(
            capabilityService: LocalCapabilityService(profile: profile)
        )
        let definition = definition(
            mlxSizeGB: 1.2,
            ggufSizeGB: 0.8
        )

        let selection = selector.bestDownloadedVariant(
            for: definition,
            downloadedVariantIds: ["fake-mlx", "fake-gguf"]
        )

        XCTAssertEqual(selection?.variant.id, "fake-mlx")
        XCTAssertEqual(selection?.variant.backend, .mlx)
    }

    func testBestDownloadedVariantPrefersSaferGGUFWhenMLXExceedsRecommendedBudget() {
        let profile = fakeProfile(memoryMB: 7_700)
        let selector = LocalRuntimeVariantSelector(
            capabilityService: LocalCapabilityService(profile: profile)
        )
        let definition = definition(
            mlxSizeGB: 3.2,
            ggufSizeGB: 1.1
        )

        let selection = selector.bestDownloadedVariant(
            for: definition,
            downloadedVariantIds: ["fake-mlx", "fake-gguf"]
        )

        XCTAssertEqual(selection?.variant.id, "fake-gguf")
        XCTAssertEqual(selection?.variant.backend, .llama)
    }

    func testGGUFFallbackRequiresDownloadedCompatibleSibling() {
        let profile = fakeProfile(memoryMB: 7_700)
        let selector = LocalRuntimeVariantSelector(
            capabilityService: LocalCapabilityService(profile: profile)
        )
        let definition = definition(
            mlxSizeGB: 1.2,
            ggufSizeGB: 1.1
        )

        XCTAssertEqual(
            selector.ggufFallbackVariant(
                for: definition,
                downloadedVariantIds: ["fake-mlx", "fake-gguf"],
                excluding: "fake-mlx"
            )?.id,
            "fake-gguf"
        )

        XCTAssertNil(
            selector.ggufFallbackVariant(
                for: definition,
                downloadedVariantIds: ["fake-mlx"],
                excluding: "fake-mlx"
            )
        )
    }

    func testGGUFFallbackRejectsUnsupportedSibling() {
        let profile = fakeProfile(memoryMB: 7_700)
        let selector = LocalRuntimeVariantSelector(
            capabilityService: LocalCapabilityService(profile: profile)
        )
        let unsupportedGGUF = variant(
            id: "qwen3-test-gguf",
            backend: .llama,
            sizeGB: 1.1,
            minimumRAMGB: 6
        )
        let definition = LocalModelDefinition(
            id: "fake-definition",
            familyId: "fake",
            familyName: "Fake",
            icon: "cpu",
            displayName: "Fake",
            description: "Fake model",
            tags: [.recommended],
            capabilities: [.text],
            highlights: ["test"],
            variants: [
                variant(id: "fake-mlx", backend: .mlx, sizeGB: 1.2, minimumRAMGB: 8),
                unsupportedGGUF
            ]
        )

        XCTAssertNil(
            selector.ggufFallbackVariant(
                for: definition,
                downloadedVariantIds: ["fake-mlx", "qwen3-test-gguf"],
                excluding: "fake-mlx"
            )
        )
    }

    private func fakeProfile(memoryMB: Int) -> DeviceCapabilityProfile {
        DeviceCapabilityProfile(
            deviceIdentifier: "FakeDevice",
            displayName: "Fake Device",
            physicalMemoryBytes: UInt64(memoryMB) * 1_048_576,
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 18,
                minorVersion: 0,
                patchVersion: 0
            ),
            isSimulator: false,
            isIPad: false
        )
    }

    private func definition(
        mlxSizeGB: Double,
        ggufSizeGB: Double
    ) -> LocalModelDefinition {
        LocalModelDefinition(
            id: "fake-definition",
            familyId: "fake",
            familyName: "Fake",
            icon: "cpu",
            displayName: "Fake",
            description: "Fake model",
            tags: [.recommended],
            capabilities: [.text],
            highlights: ["test"],
            variants: [
                variant(id: "fake-mlx", backend: .mlx, sizeGB: mlxSizeGB, minimumRAMGB: 8),
                variant(id: "fake-gguf", backend: .llama, sizeGB: ggufSizeGB, minimumRAMGB: 6)
            ]
        )
    }

    private func variant(
        id: String,
        backend: EngineType,
        sizeGB: Double,
        minimumRAMGB: Int
    ) -> LocalModelVariant {
        LocalModelVariant(
            id: id,
            definitionId: "fake-definition",
            backend: backend,
            artifactFormat: backend.modelFormat,
            quantization: backend == .mlx ? "4-bit" : "Q4_K_M",
            minimumIOSVersion: backend.minimumIOSVersion,
            minimumRAMGB: minimumRAMGB,
            preferredDevices: ["iPhone"],
            downloadSource: .direct(url: "https://example.com/\(id)"),
            sizeGB: sizeGB,
            sizeMB: Int(sizeGB * 1024),
            isExperimental: false,
            minimumDeviceDescription: "iPhone"
        )
    }
}
