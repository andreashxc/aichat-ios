import Foundation

/// Единый протокол для всех inference engines (MLX, llama.cpp, etc.)
///
/// Этот протокол определяет общий интерфейс для работы с локальными LLM моделями,
/// независимо от используемого backend (MLX Swift, llmfarm_core, etc.)
protocol LocalInferenceEngine: Actor {
    /// Информация о загруженной модели
    var modelInfo: LoadedModelInfo? { get }

    /// Загрузить модель из файловой системы
    /// - Parameters:
    ///   - modelPath: Путь к модели (файл для GGUF, директория для MLX)
    ///   - config: Конфигурация модели
    func loadModel(modelPath: String, config: ModelConfig) async throws

    /// Генерация текста с streaming
    /// - Parameters:
    ///   - prompt: Backend-specific rendered prompt and generation options
    ///   - onToken: Callback для каждого сгенерированного токена
    func generate(
        prompt: LocalRenderedPrompt,
        onToken: @escaping (String) -> Void
    ) async throws

    /// Очистка ресурсов (освобождение памяти, GPU)
    func cleanup() async
}

/// Информация о загруженной модели
struct LoadedModelInfo {
    /// ID модели
    let modelId: String

    /// Размер контекста
    let contextSize: Int

    /// Размер словаря
    let vocabularySize: Int

    /// Тип используемого engine
    let engineType: EngineType

    /// Путь к модели
    let modelPath: String

    /// Использует ли Metal (GPU)
    let usesMetal: Bool
}

/// Ошибки inference engine
enum InferenceEngineError: Error, LocalizedError {
    case modelNotLoaded
    case invalidModelPath(String)
    case invalidFormat(expected: String, got: String)
    case loadFailed(String)
    case generationFailed(String)
    case outOfMemory
    case unsupportedDevice

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model is not loaded. Please load a model first."
        case .invalidModelPath(let path):
            return "Invalid model path: \(path)"
        case .invalidFormat(let expected, let got):
            return "Invalid model format. Expected \(expected), got \(got)"
        case .loadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .outOfMemory:
            return "Out of memory. Try using a smaller model or closing other apps."
        case .unsupportedDevice:
            return "This feature is not supported on your device."
        }
    }
}
