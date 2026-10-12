import XCTest
@testable import AiChat

final class LocalModelRegistryTests: XCTestCase {
    func testQwen3RegistryIncludesGGUFAndMLXVariants() {
        let definition = LocalModelRegistry.shared.definition(for: "qwen3-1.7b", includeExperimental: true)

        XCTAssertNotNil(definition)
        XCTAssertEqual(definition?.variants.count, 1)
        XCTAssertEqual(definition?.variants.first?.artifactFormat, .mlx)
        XCTAssertTrue(definition?.capabilities.contains(.thinking) == true)
    }

    func testReleaseCatalogExcludesUnverifiedOrRestrictedDownloads() {
        for id in ["qwen-2.5-3b", "qwen3.5-2b", "qwen3.5-4b", "gemma-2-2b", "gemma-3-1b"] {
            XCTAssertNil(LocalModelRegistry.shared.definition(for: id, includeExperimental: true))
        }
    }

    func testLargeModelReturnsWarningInsteadOfBlock() {
        let variant = LocalModelVariant(
            id: "warning-test",
            definitionId: "warning-test",
            backend: .llama,
            artifactFormat: .gguf,
            quantization: "Q4_K_M",
            minimumIOSVersion: EngineType.llama.minimumIOSVersion,
            minimumRAMGB: 1,
            preferredDevices: ["iPhone / iPad"],
            downloadSource: .direct(url: "https://example.com/model.gguf"),
            sizeGB: 3.5,
            sizeMB: Int(3.5 * 1024),
            isExperimental: false,
            minimumDeviceDescription: "iPhone / iPad"
        )

        let profile = DeviceCapabilityProfile(
            deviceIdentifier: "iPhone16,1",
            displayName: "iPhone 15 Pro",
            physicalMemoryBytes: UInt64(7_644) * 1_048_576,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0),
            isSimulator: false,
            isIPad: false
        )
        let state = LocalCapabilityService(profile: profile).supportState(for: variant)
        if case .supportedWithWarning = state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected large model to return supportedWithWarning, got \(state)")
        }
    }
}
