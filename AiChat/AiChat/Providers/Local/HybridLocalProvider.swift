import Foundation

/// Hybrid Local Provider - автоматически выбирает между MLX и llama.cpp
///
/// Логика выбора engine:
/// - iOS 18+ real devices with at least 7,500 MB physical memory -> MLX Engine when selected or automatic
/// - Other supported real devices -> Llama Engine (SwiftLlama / GGUF)
///
/// Поддерживает:
/// - Автоматический выбор engine на основе DeviceCapabilities
/// - Автоматический fallback MLX → llama.cpp при ошибках
/// - Загрузка моделей в правильном формате (MLX или GGUF)
/// - Streaming generation без блокировки UI
/// - Управление lifecycle моделей
actor HybridLocalProvider {

    // MARK: - Properties

    private let storage = ModelStorage()

    nonisolated private var downloadManager: ModelDownloadManager {
        ModelDownloadManager.shared
    }

    /// Текущий активный engine
    private var currentEngine: LocalInferenceEngine?

    /// Тип текущего engine
    private var currentEngineType: EngineType?

    /// ID текущей загруженной модели
    private var loadedModelId: String?

    /// Кэшированная информация о модели
    private var cachedModelInfo: LoadedModelInfo?

    /// Флаг показывает, что произошел fallback с MLX на llama.cpp
    private var didFallbackToLlama: Bool = false

    // MARK: - Engine Selection

    /// Определить какой engine использовать для устройства
    private func selectEngine() -> EngineType {
        let recommended = DeviceCapabilities.recommendedEngine()
        Logger.shared.info("🔍 HybridLocalProvider: Selected engine: \(recommended.displayName)")
        return recommended
    }

    /// Создать engine указанного типа
    private func createEngine(type: EngineType) -> LocalInferenceEngine {
        switch type {
        case .mlx:
            Logger.shared.info("🚀 Creating MLX Engine")
            return MLXEngine()

        case .llama:
            Logger.shared.info("🦙 Creating Llama Engine")
            return LlamaEngine()
        }
    }

    // MARK: - Model Loading

    /// Загрузить модель
    /// - Parameters:
    ///   - modelId: ID модели из каталога
    ///   - config: Конфигурация модели (опционально)
    func loadModel(modelId: String, config: ModelConfig? = nil) async throws {
        Logger.shared.info("📦 HybridLocalProvider: Loading model: \(modelId)")

        #if targetEnvironment(simulator)
        Logger.shared.error("❌ Local model inference is not supported in iOS Simulator")
        throw HybridProviderError.simulatorNotSupported
        #else

        // Проверить что модель загружена
        guard downloadManager.isModelDownloaded(modelId) else {
            Logger.shared.error("❌ Model not downloaded: \(modelId)")
            throw HybridProviderError.modelNotDownloaded(modelId: modelId)
        }

        guard let detectedFormat = storage.detectFormat(for: modelId) else {
            Logger.shared.error("❌ Model not found on disk: \(modelId)")
            throw HybridProviderError.modelNotFound(modelId: modelId)
        }

        var format = detectedFormat

        Logger.shared.info("📁 Model format on disk: \(format.rawValue)")

        // Force GGUF if preference is set (for stability)
        if ModelPreferences.forceGGUF && format == .mlx {
            let ggufURL = storage.fileURL(for: modelId, format: .gguf)
            if FileManager.default.fileExists(atPath: ggufURL.path) {
                Logger.shared.info("🔧 Force GGUF enabled, switching from MLX to GGUF")
                format = .gguf
            } else {
                Logger.shared.info("⚠️ Force GGUF enabled but no GGUF available, will try MLX")
            }
        }

        Logger.shared.info("📁 Using format: \(format.rawValue)")

        var engineType = selectEngine()
        if !isCompatible(format: format, engineType: engineType) {
            engineType = format == .mlx ? .mlx : .llama
        }

        try await loadArtifact(
            modelId: modelId,
            format: format,
            preferredEngine: engineType,
            config: config,
            allowLlamaFallback: true
        )
        #endif
    }

    func loadVariant(_ variant: LocalModelVariant, config: ModelConfig? = nil) async throws {
        Logger.shared.info("📦 HybridLocalProvider: Loading variant: \(variant.id)")

        #if targetEnvironment(simulator)
        Logger.shared.error("❌ Local model inference is not supported in iOS Simulator")
        throw HybridProviderError.simulatorNotSupported
        #else

        if variant.artifactFormat == .mlx, !storage.isMLXModelComplete(modelId: variant.id) {
            throw HybridProviderError.modelIncomplete(modelId: variant.id)
        }

        if variant.artifactFormat == .mlx, let sizeBytes = storage.getModelSize(modelId: variant.id) {
            let sizeGB = Double(sizeBytes) / 1_073_741_824.0
            let maxRecommended = DeviceCapabilities.maxRecommendedModelSize
            if sizeGB > maxRecommended {
                Logger.shared.info("⚠️ MLX model exceeds recommended budget: \(String(format: "%.2f", sizeGB))GB > \(String(format: "%.2f", maxRecommended))GB")
            }
        }

        try await loadArtifact(
            modelId: variant.id,
            format: variant.artifactFormat,
            preferredEngine: variant.backend,
            config: config,
            allowLlamaFallback: false
        )
        #endif
    }

    private func loadArtifact(
        modelId: String,
        format initialFormat: ModelFormat,
        preferredEngine: EngineType,
        config: ModelConfig?,
        allowLlamaFallback: Bool
    ) async throws {
        var format = initialFormat
        var engineType = preferredEngine
        didFallbackToLlama = false

        if format == .mlx {
            if !storage.isMLXModelComplete(modelId: modelId) {
                Logger.shared.error("❌ MLX model is incomplete or corrupted")
                let ggufURL = storage.fileURL(for: modelId, format: .gguf)
                if FileManager.default.fileExists(atPath: ggufURL.path) {
                    Logger.shared.info("🔄 Falling back to GGUF due to incomplete MLX model")
                    format = .gguf
                    engineType = .llama
                    didFallbackToLlama = true
                } else {
                    throw HybridProviderError.modelIncomplete(modelId: modelId)
                }
            }
        }

        if format == .mlx, let sizeBytes = storage.getModelSize(modelId: modelId) {
            let sizeGB = Double(sizeBytes) / 1_073_741_824.0
            let maxRecommended = DeviceCapabilities.maxRecommendedModelSize
            if sizeGB > maxRecommended {
                Logger.shared.info("⚠️ MLX model exceeds recommended budget: \(String(format: "%.2f", sizeGB))GB > \(String(format: "%.2f", maxRecommended))GB")
            }
        }

        if !isCompatible(format: format, engineType: engineType) {
            Logger.shared.info("⚠️ Format \(format.rawValue) not compatible with \(engineType.displayName)")
            engineType = format == .mlx ? .mlx : .llama
            Logger.shared.info("🔄 Falling back to \(engineType.displayName) for \(format.rawValue) format")
        }

        var loadSucceeded = false

        while !loadSucceeded {
            if currentEngineType != engineType {
                if let engine = currentEngine {
                    await engine.cleanup()
                }
                currentEngine = createEngine(type: engineType)
                currentEngineType = engineType
            }

            let modelPath = storage.fileURL(for: modelId, format: format).path
            Logger.shared.info("📂 Model path: \(modelPath)")

            let modelConfig: ModelConfig
            if let config = config {
                modelConfig = config
            } else {
                let ramBytes = DeviceCapabilities.deviceRAMInBytes()
                let modelSizeBytes = UInt64(storage.getModelSize(modelId: modelId) ?? 0)
                modelConfig = format == .mlx
                    ? ModelConfig.mlxOptimized(deviceRAM: ramBytes)
                    : ModelConfig.llamaOptimized(deviceRAM: ramBytes, modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil)
            }

            Logger.shared.info("⏳ Loading model into \(engineType.displayName)...")

            do {
                try await currentEngine?.loadModel(modelPath: modelPath, config: modelConfig)
                loadedModelId = modelId
                loadSucceeded = true

                Logger.shared.info("✅ Model loaded successfully with \(engineType.displayName)")

                if let engine = currentEngine,
                   let modelInfo = await engine.modelInfo {
                    cachedModelInfo = modelInfo
                    Logger.shared.info("""
                    📊 Model Info:
                       - Engine: \(modelInfo.engineType.displayName)
                       - Context: \(modelInfo.contextSize) tokens
                       - Path: \(modelInfo.modelPath)
                       - Metal: \(modelInfo.usesMetal ? "✅" : "❌")
                       \(didFallbackToLlama ? "- ⚠️ Fallback mode (MLX failed)" : "")
                    """)
                }

            } catch {
                Logger.shared.error("❌ Failed to load with \(engineType.displayName): \(error.localizedDescription)")

                if allowLlamaFallback, engineType == .mlx && !didFallbackToLlama {
                    Logger.shared.info("🔄 Attempting fallback to llama.cpp...")
                    let ggufURL = storage.fileURL(for: modelId, format: .gguf)
                    if FileManager.default.fileExists(atPath: ggufURL.path) {
                        engineType = .llama
                        didFallbackToLlama = true
                        Logger.shared.info("✅ GGUF model found, switching to llama.cpp")
                        continue
                    } else {
                        Logger.shared.error("❌ No GGUF fallback available")
                        throw error
                    }
                } else {
                    throw error
                }
            }
        }
    }

    /// Проверить совместимость формата и engine
    private func isCompatible(format: ModelFormat, engineType: EngineType) -> Bool {
        switch (format, engineType) {
        case (.gguf, .llama):
            return true  // GGUF работает с llama.cpp
        case (.mlx, .mlx):
            return true  // MLX работает с MLX engine
        case (.gguf, .mlx):
            return false // MLX engine не понимает GGUF
        case (.mlx, .llama):
            return false // llama.cpp не понимает MLX
        }
    }

    // MARK: - Generation

    /// Генерировать текст с streaming
    /// - Parameters:
    ///   - prompt: Промпт для генерации
    ///   - maxTokens: Максимум токенов
    ///   - temperature: Температура (0.0-2.0)
    ///   - onToken: Callback для каждого токена
    func generate(
        prompt: LocalRenderedPrompt,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let engine = currentEngine else {
            Logger.shared.error("❌ No engine loaded")
            throw HybridProviderError.noEngineLoaded
        }

        guard loadedModelId != nil else {
            Logger.shared.error("❌ No model loaded")
            throw HybridProviderError.noModelLoaded
        }

        Logger.shared.info("🚀 Starting generation...")
        Logger.shared.info("📝 Prompt: \(prompt.text.prefix(100))...")
        Logger.shared.info("⚙️ Max tokens: \(prompt.options.maxTokens), Temperature: \(prompt.options.temperature), TopP: \(prompt.options.topP)")

        try await engine.generate(
            prompt: prompt,
            onToken: onToken
        )

        Logger.shared.info("✅ Generation complete")
    }

    // MARK: - Lifecycle

    /// Очистить ресурсы
    func cleanup() async {
        Logger.shared.info("🧹 HybridLocalProvider: Cleaning up...")

        if let engine = currentEngine {
            await engine.cleanup()
        }

        currentEngine = nil
        currentEngineType = nil
        loadedModelId = nil
        cachedModelInfo = nil

        Logger.shared.info("✅ Cleanup complete")
    }

    // MARK: - Info

    /// Получить информацию о текущем состоянии
    var status: ProviderStatus {
        ProviderStatus(
            engineType: currentEngineType,
            loadedModelId: loadedModelId,
            modelInfo: cachedModelInfo
        )
    }
}

// MARK: - Supporting Types

struct ProviderStatus {
    let engineType: EngineType?
    let loadedModelId: String?
    let modelInfo: LoadedModelInfo?

    var isReady: Bool {
        engineType != nil && loadedModelId != nil
    }

    var description: String {
        guard isReady else {
            return "No model loaded"
        }

        return """
        Engine: \(engineType?.displayName ?? "Unknown")
        Model: \(loadedModelId ?? "Unknown")
        Ready: ✅
        """
    }
}

// MARK: - Errors

enum HybridProviderError: Error, LocalizedError {
    case noEngineLoaded
    case noModelLoaded
    case modelNotDownloaded(modelId: String)
    case modelNotFound(modelId: String)
    case modelIncomplete(modelId: String)
    case formatMismatch(format: ModelFormat, engineType: EngineType)
    case modelTooLarge(modelId: String, sizeGB: Double, maxRecommendedGB: Double)
    case simulatorNotSupported

    var errorDescription: String? {
        switch self {
        case .noEngineLoaded:
            return "No inference engine loaded. Please load a model first."
        case .noModelLoaded:
            return "No model loaded. Please load a model first."
        case .modelNotDownloaded(let modelId):
            return "Model '\(modelId)' is not downloaded. Please download it from Settings."
        case .modelNotFound(let modelId):
            return "Model '\(modelId)' not found on disk."
        case .modelIncomplete(let modelId):
            return "Model '\(modelId)' is incomplete or corrupted. Please delete and re-download it from Settings > Manage Models."
        case .formatMismatch(let format, let engineType):
            return "Model format \(format.rawValue) is not compatible with \(engineType.displayName)"
        case .modelTooLarge(let modelId, let sizeGB, let maxRecommendedGB):
            return "Model '\(modelId)' is too large for this device (\(String(format: "%.2f", sizeGB))GB > \(String(format: "%.2f", maxRecommendedGB))GB). Please use a smaller model."
        case .simulatorNotSupported:
            return "Local models are not supported in iOS Simulator. Run the app on a real iPhone or iPad."
        }
    }
}
