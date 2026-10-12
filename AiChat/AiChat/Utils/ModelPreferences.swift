import Foundation

enum LocalBackendPreference: String, Codable, CaseIterable, Identifiable {
    case auto
    case gguf
    case mlx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .gguf:
            return "GGUF"
        case .mlx:
            return "MLX"
        }
    }
}

enum LocalThinkingModePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case automatic
    case on

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .automatic:
            return "Auto"
        case .on:
            return "On"
        }
    }
}

enum ModelPreferences {
    private static let localBackendPreferenceKey = "local_backend_preference"
    private static let localIncludeExperimentalKey = "local_include_experimental"
    private static let localThinkingModeKey = "local_thinking_mode"

    // MARK: - Local Model Preferences

    static var localBackendPreference: LocalBackendPreference {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: localBackendPreferenceKey),
                  let preference = LocalBackendPreference(rawValue: rawValue) else {
                return .auto
            }
            return preference
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: localBackendPreferenceKey)
        }
    }

    static var localIncludeExperimental: Bool {
        get {
            if UserDefaults.standard.object(forKey: localIncludeExperimentalKey) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: localIncludeExperimentalKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: localIncludeExperimentalKey)
        }
    }

    static var localThinkingMode: LocalThinkingModePreference {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: localThinkingModeKey),
                  let preference = LocalThinkingModePreference(rawValue: rawValue) else {
                return .automatic
            }
            return preference
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: localThinkingModeKey)
        }
    }

    static var forceGGUF: Bool {
        get {
            localBackendPreference == .gguf
        }
        set {
            localBackendPreference = newValue ? .gguf : .auto
        }
    }
}
