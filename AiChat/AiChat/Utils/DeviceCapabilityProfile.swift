import Foundation

struct DeviceCapabilityProfile: Equatable, Sendable {
    static let minimumMLXMemoryMB = 7_500

    let deviceIdentifier: String
    let displayName: String
    let physicalMemoryBytes: UInt64
    let supportsMLX: Bool
    let recommendedBackend: EngineType
    let maxRecommendedModelSizeGB: Double
    let warnings: [String]
    let operatingSystemVersion: OperatingSystemVersion
    let isSimulator: Bool
    let isIPad: Bool

    var physicalMemoryMB: Int {
        Int(physicalMemoryBytes / 1_048_576)
    }

    var supportsFoundationModelsRuntime: Bool {
        operatingSystemVersion.majorVersion >= 26
    }

    init(
        deviceIdentifier: String,
        displayName: String,
        physicalMemoryBytes: UInt64,
        supportsMLX: Bool? = nil,
        recommendedBackend: EngineType? = nil,
        maxRecommendedModelSizeGB: Double? = nil,
        warnings: [String]? = nil,
        operatingSystemVersion: OperatingSystemVersion,
        isSimulator: Bool,
        isIPad: Bool,
        backendPreference: LocalBackendPreference = .auto
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.displayName = displayName
        self.physicalMemoryBytes = physicalMemoryBytes
        self.operatingSystemVersion = operatingSystemVersion
        self.isSimulator = isSimulator
        self.isIPad = isIPad

        let mlxSupport = supportsMLX ?? Self.evaluateMLXSupport(
            physicalMemoryBytes: physicalMemoryBytes,
            operatingSystemVersion: operatingSystemVersion,
            isSimulator: isSimulator
        )
        self.supportsMLX = mlxSupport
        self.recommendedBackend = recommendedBackend ?? Self.recommendedBackend(
            supportsMLX: mlxSupport,
            backendPreference: backendPreference
        )
        self.maxRecommendedModelSizeGB = maxRecommendedModelSizeGB ?? Self.maxRecommendedModelSizeGB(
            physicalMemoryBytes: physicalMemoryBytes
        )
        self.warnings = warnings ?? Self.warnings(
            physicalMemoryBytes: physicalMemoryBytes,
            supportsMLX: mlxSupport,
            operatingSystemVersion: operatingSystemVersion,
            isSimulator: isSimulator
        )
    }

    func supportsIOSVersion(_ minimumIOSVersion: Double) -> Bool {
        let requiredMajor = Int(minimumIOSVersion)
        let requiredMinor = Int(((minimumIOSVersion - Double(requiredMajor)) * 10).rounded())

        if operatingSystemVersion.majorVersion != requiredMajor {
            return operatingSystemVersion.majorVersion > requiredMajor
        }
        return operatingSystemVersion.minorVersion >= requiredMinor
    }

    func meetsMinimumRAMGB(_ minimumRAMGB: Int) -> Bool {
        physicalMemoryMB >= Self.minimumPhysicalMemoryMB(forNominalGB: minimumRAMGB)
    }

    static func current(
        deviceIdentifier: String,
        displayName: String,
        physicalMemoryBytes: UInt64,
        operatingSystemVersion: OperatingSystemVersion,
        isSimulator: Bool,
        isIPad: Bool,
        backendPreference: LocalBackendPreference = ModelPreferences.localBackendPreference
    ) -> DeviceCapabilityProfile {
        DeviceCapabilityProfile(
            deviceIdentifier: deviceIdentifier,
            displayName: displayName,
            physicalMemoryBytes: physicalMemoryBytes,
            operatingSystemVersion: operatingSystemVersion,
            isSimulator: isSimulator,
            isIPad: isIPad,
            backendPreference: backendPreference
        )
    }

    static func minimumPhysicalMemoryMB(forNominalGB nominalGB: Int) -> Int {
        switch nominalGB {
        case ...0:
            return 0
        case 1..<6:
            return nominalGB * 1024
        case 6..<8:
            return 5_500
        case 8..<12:
            return minimumMLXMemoryMB
        case 12..<16:
            return 11_250
        default:
            return Int(Double(nominalGB * 1024) * 0.92)
        }
    }

    static func evaluateMLXSupport(
        physicalMemoryBytes: UInt64,
        operatingSystemVersion: OperatingSystemVersion,
        isSimulator: Bool
    ) -> Bool {
        guard !isSimulator else { return false }
        guard operatingSystemVersion.majorVersion >= 18 else { return false }

        let memoryMB = Int(physicalMemoryBytes / 1_048_576)
        return memoryMB >= minimumMLXMemoryMB
    }

    static func recommendedBackend(
        supportsMLX: Bool,
        backendPreference: LocalBackendPreference
    ) -> EngineType {
        switch backendPreference {
        case .auto:
            return supportsMLX ? .mlx : .llama
        case .mlx:
            return supportsMLX ? .mlx : .llama
        case .gguf:
            return .llama
        }
    }

    static func maxRecommendedModelSizeGB(physicalMemoryBytes: UInt64) -> Double {
        let memoryMB = Int(physicalMemoryBytes / 1_048_576)

        if memoryMB >= minimumPhysicalMemoryMB(forNominalGB: 16) {
            return 5.0
        }
        if memoryMB >= minimumPhysicalMemoryMB(forNominalGB: 12) {
            return 4.0
        }
        if memoryMB >= minimumPhysicalMemoryMB(forNominalGB: 8) {
            return 2.5
        }
        if memoryMB >= minimumPhysicalMemoryMB(forNominalGB: 6) {
            return 1.5
        }
        return 0.5
    }

    private static func warnings(
        physicalMemoryBytes: UInt64,
        supportsMLX: Bool,
        operatingSystemVersion: OperatingSystemVersion,
        isSimulator: Bool
    ) -> [String] {
        var result: [String] = []

        if isSimulator {
            result.append("Local model inference is disabled in Simulator.")
        }
        if operatingSystemVersion.majorVersion < 18 {
            result.append("AiChat local runtimes require iOS 18.0 or newer.")
        }
        if !supportsMLX {
            let memoryMB = Int(physicalMemoryBytes / 1_048_576)
            if memoryMB < minimumMLXMemoryMB {
                result.append("MLX requires at least \(minimumMLXMemoryMB) MB of physical memory.")
            }
        }
        if operatingSystemVersion.majorVersion < 26 {
            result.append("Foundation Models require iOS 26.0 or newer.")
        }

        return result
    }

    static func == (lhs: DeviceCapabilityProfile, rhs: DeviceCapabilityProfile) -> Bool {
        lhs.deviceIdentifier == rhs.deviceIdentifier &&
            lhs.displayName == rhs.displayName &&
            lhs.physicalMemoryBytes == rhs.physicalMemoryBytes &&
            lhs.supportsMLX == rhs.supportsMLX &&
            lhs.recommendedBackend == rhs.recommendedBackend &&
            lhs.maxRecommendedModelSizeGB == rhs.maxRecommendedModelSizeGB &&
            lhs.warnings == rhs.warnings &&
            lhs.operatingSystemVersion.majorVersion == rhs.operatingSystemVersion.majorVersion &&
            lhs.operatingSystemVersion.minorVersion == rhs.operatingSystemVersion.minorVersion &&
            lhs.operatingSystemVersion.patchVersion == rhs.operatingSystemVersion.patchVersion &&
            lhs.isSimulator == rhs.isSimulator &&
            lhs.isIPad == rhs.isIPad
    }
}
