import Foundation

enum AudioTranscriptionModel: String, CaseIterable, Identifiable {
    case tiny
    case base

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:
            return "Tiny (On-device, fastest)"
        case .base:
            return "Base (Apple Speech, network may be used)"
        }
    }
}

enum AudioTranscriptionPreferences {
    private static let modelKey = "audio_transcription_model"

    static func selectedModel() -> AudioTranscriptionModel {
        if let rawValue = UserDefaults.standard.string(forKey: modelKey),
           let model = AudioTranscriptionModel(rawValue: rawValue) {
            return model
        }
        return .tiny
    }

    static func saveSelectedModel(_ model: AudioTranscriptionModel) {
        UserDefaults.standard.set(model.rawValue, forKey: modelKey)
    }
}
