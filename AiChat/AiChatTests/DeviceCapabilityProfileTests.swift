import XCTest
@testable import AiChat

final class DeviceCapabilityProfileTests: XCTestCase {
    func testLowMemoryIPhoneFallsBackToLlamaAndBlocksSixGBModels() {
        let profile = fakeProfile(memoryMB: 3_800, displayName: "Low-memory iPhone")
        let state = LocalCapabilityService(profile: profile).supportState(for: variant(backend: .llama, minimumRAMGB: 6))

        XCTAssertFalse(profile.supportsMLX)
        XCTAssertEqual(profile.recommendedBackend, .llama)
        XCTAssertFalse(state.isAvailable)
        XCTAssertEqual(profile.maxRecommendedModelSizeGB, 0.5)
    }

    func testSixGBIPhoneSupportsLlamaOnly() {
        let profile = fakeProfile(memoryMB: 5_700, displayName: "6GB iPhone")
        let service = LocalCapabilityService(profile: profile)

        XCTAssertFalse(profile.supportsMLX)
        XCTAssertEqual(profile.recommendedBackend, .llama)
        XCTAssertEqual(service.supportState(for: variant(backend: .llama, minimumRAMGB: 6)), .supported)
        XCTAssertFalse(service.supportState(for: variant(backend: .mlx, minimumRAMGB: 8)).isAvailable)
    }

    func testEightGBIPhoneProUsesMBBasedMLXThreshold() {
        let profile = fakeProfile(memoryMB: 7_644, displayName: "8GB iPhone Pro")
        let state = LocalCapabilityService(profile: profile).supportState(for: variant(backend: .mlx, minimumRAMGB: 8))

        XCTAssertEqual(profile.physicalMemoryMB, 7_644)
        XCTAssertEqual(Int(profile.physicalMemoryBytes / 1_073_741_824), 7)
        XCTAssertTrue(profile.supportsMLX)
        XCTAssertEqual(profile.recommendedBackend, .mlx)
        XCTAssertEqual(state, .supported)
    }

    func testTwelveGBIPhoneOrIPadAllowsLargerLocalBudget() {
        let profile = fakeProfile(memoryMB: 11_500, displayName: "12GB iPad", isIPad: true)
        let service = LocalCapabilityService(profile: profile)

        XCTAssertTrue(profile.supportsMLX)
        XCTAssertEqual(profile.maxRecommendedModelSizeGB, 4.0)
        XCTAssertEqual(service.supportState(for: variant(backend: .mlx, minimumRAMGB: 8, sizeGB: 3.2)), .supported)
    }

    func testSimulatorDisablesLocalModels() {
        let profile = fakeProfile(memoryMB: 16_000, displayName: "Simulator", isSimulator: true)
        let state = LocalCapabilityService(profile: profile).supportState(for: variant(backend: .llama, minimumRAMGB: 4))

        XCTAssertFalse(profile.supportsMLX)
        XCTAssertFalse(state.isAvailable)
        XCTAssertEqual(state.reason, "Local models run only on a real iPhone or iPad.")
    }

    func testIOSBelowMLXRequirementDoesNotExposeMLX() {
        let profile = fakeProfile(memoryMB: 7_644, majorVersion: 17, displayName: "iOS 17 iPhone Pro")
        let state = LocalCapabilityService(profile: profile).supportState(for: variant(backend: .mlx, minimumRAMGB: 8))

        XCTAssertFalse(profile.supportsMLX)
        XCTAssertEqual(profile.recommendedBackend, .llama)
        XCTAssertFalse(state.isAvailable)
        XCTAssertEqual(state.reason, "Requires iOS 18.0 or newer.")
    }

    func testIOS26FoundationModelsCapableDeviceKeepsLocalMLXAvailable() {
        let profile = fakeProfile(memoryMB: 7_644, majorVersion: 26, displayName: "iOS 26 iPhone Pro")
        let state = LocalCapabilityService(profile: profile).supportState(for: variant(backend: .mlx, minimumRAMGB: 8))

        XCTAssertTrue(profile.supportsFoundationModelsRuntime)
        XCTAssertTrue(profile.supportsMLX)
        XCTAssertEqual(profile.recommendedBackend, .mlx)
        XCTAssertFalse(profile.warnings.contains("Foundation Models require iOS 26.0 or newer."))
        XCTAssertEqual(state, .supported)
    }

    private func fakeProfile(
        memoryMB: Int,
        majorVersion: Int = 18,
        displayName: String,
        isSimulator: Bool = false,
        isIPad: Bool = false
    ) -> DeviceCapabilityProfile {
        DeviceCapabilityProfile(
            deviceIdentifier: displayName.replacingOccurrences(of: " ", with: ""),
            displayName: displayName,
            physicalMemoryBytes: UInt64(memoryMB) * 1_048_576,
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: majorVersion,
                minorVersion: 0,
                patchVersion: 0
            ),
            isSimulator: isSimulator,
            isIPad: isIPad
        )
    }

    private func variant(
        backend: EngineType,
        minimumRAMGB: Int,
        sizeGB: Double = 1.0
    ) -> LocalModelVariant {
        LocalModelVariant(
            id: "test-\(backend.rawValue)-\(minimumRAMGB)",
            definitionId: "test",
            backend: backend,
            artifactFormat: backend.modelFormat,
            quantization: "test",
            minimumIOSVersion: backend.minimumIOSVersion,
            minimumRAMGB: minimumRAMGB,
            preferredDevices: ["Test"],
            downloadSource: .direct(url: "https://example.com/model"),
            sizeGB: sizeGB,
            sizeMB: Int(sizeGB * 1024),
            isExperimental: false,
            minimumDeviceDescription: "iPhone / iPad"
        )
    }
}
