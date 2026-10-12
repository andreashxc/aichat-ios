import Foundation
import UIKit

struct DeviceCapabilities {
    static func currentProfile(
        backendPreference: LocalBackendPreference = ModelPreferences.localBackendPreference
    ) -> DeviceCapabilityProfile {
        DeviceCapabilityProfile.current(
            deviceIdentifier: deviceModel(),
            displayName: deviceDisplayName(),
            physicalMemoryBytes: deviceRAMInBytes(),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion,
            isSimulator: isRunningInSimulator,
            isIPad: isIPad(),
            backendPreference: backendPreference
        )
    }

    static func supportsMLX() -> Bool {
        let profile = currentProfile()
        Logger.shared.info("MLX support: \(profile.supportsMLX) on \(profile.displayName), \(profile.physicalMemoryMB) MB")
        return profile.supportsMLX
    }

    static func deviceRAMInMB() -> Int {
        Int(deviceRAMInBytes() / 1_048_576)
    }

    static func deviceRAMInBytes() -> UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    static func processorCount() -> Int {
        ProcessInfo.processInfo.processorCount
    }

    static func activeProcessorCount() -> Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
    }

    static func deviceDisplayName() -> String {
        let model = deviceModel()
        let modelMap: [String: String] = [
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            "iPad14,3": "iPad Pro 11\" (M2)",
            "iPad14,4": "iPad Pro 12.9\" (M2)",
            "iPad14,5": "iPad Pro 11\" (M4)",
            "iPad14,6": "iPad Pro 13\" (M4)",
            "iPad13,4": "iPad Pro 11\" (M1)",
            "iPad13,5": "iPad Pro 12.9\" (M1)",
            "iPad13,8": "iPad Pro 11\" (M1)",
            "iPad13,9": "iPad Pro 12.9\" (M1)",
            "iPad13,16": "iPad Air (M1)",
            "iPad13,17": "iPad Air (M1)",
            "iPad14,8": "iPad Air 11\" (M2)",
            "iPad14,9": "iPad Air 13\" (M2)"
        ]

        return modelMap[model] ?? model
    }

    static func isIPad() -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var recommendedGPUCacheSize: Int {
        let profile = currentProfile()

        if profile.physicalMemoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 16) {
            return 2_048 * 1024 * 1024
        }
        if profile.physicalMemoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 12) {
            return 1_024 * 1024 * 1024
        }
        if profile.physicalMemoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 8) {
            return 512 * 1024 * 1024
        }
        return 256 * 1024 * 1024
    }

    static var recommendedGPUCacheSizeMB: Int {
        recommendedGPUCacheSize / 1024 / 1024
    }

    static func recommendedEngine() -> EngineType {
        let profile = currentProfile()
        Logger.shared.info("Recommended local backend: \(profile.recommendedBackend.displayName)")
        return profile.recommendedBackend
    }

    static func supports(engine: EngineType) -> Bool {
        let profile = currentProfile()
        switch engine {
        case .mlx:
            return profile.supportsMLX
        case .llama:
            return !profile.isSimulator && profile.supportsIOSVersion(engine.minimumIOSVersion)
        }
    }

    static func estimatedTokensPerSecond(for engine: EngineType, modelSizeGB: Double) -> Double {
        let profile = currentProfile()
        let baseSpeed: Double

        switch engine {
        case .mlx:
            baseSpeed = profile.physicalMemoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 12) ? 25.0 : 15.0
        case .llama:
            baseSpeed = profile.physicalMemoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 8) ? 10.0 : 5.0
        }

        let modelFactor = max(0.3, 1.0 - (modelSizeGB / 10.0))
        return baseSpeed * modelFactor
    }

    static var maxRecommendedModelSize: Double {
        currentProfile().maxRecommendedModelSizeGB
    }

    static func diagnosticInfo() -> String {
        let profile = currentProfile()
        let warningText = profile.warnings.isEmpty ? "None" : profile.warnings.joined(separator: "\n")

        return """
        Device Information
        ------------------
        Device:           \(profile.displayName)
        Model ID:         \(profile.deviceIdentifier)
        Device Type:      \(profile.isIPad ? "iPad" : "iPhone")
        iOS Version:      \(UIDevice.current.systemVersion)
        Simulator:        \(profile.isSimulator ? "Yes" : "No")

        Memory & Processing
        -------------------
        RAM:              \(profile.physicalMemoryMB) MB
        Processors:       \(processorCount()) cores
        Active Cores:     \(activeProcessorCount())

        Local Model Capabilities
        ------------------------
        MLX Support:      \(profile.supportsMLX ? "Yes" : "No")
        Recommended:      \(profile.recommendedBackend.displayName)
        GPU Cache:        \(recommendedGPUCacheSizeMB) MB
        Max Model Size:   \(String(format: "%.1f", profile.maxRecommendedModelSizeGB)) GB

        Performance Estimates
        ---------------------
        MLX (2GB model):   \(String(format: "%.1f", estimatedTokensPerSecond(for: .mlx, modelSizeGB: 2.0))) tokens/sec
        llama (2GB model): \(String(format: "%.1f", estimatedTokensPerSecond(for: .llama, modelSizeGB: 2.0))) tokens/sec

        Warnings
        --------
        \(warningText)
        """
    }

    static func shortDiagnostic() -> String {
        let profile = currentProfile()
        return "\(profile.displayName) | \(profile.physicalMemoryMB) MB RAM | MLX: \(profile.supportsMLX) | Backend: \(profile.recommendedBackend.displayName)"
    }

    private static var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
