import Foundation

/// Llama.cpp inference engine wrapper
///
/// Обертка над LlamaContext, реализующая протокол LocalInferenceEngine
/// для использования в HybridLocalProvider
///
/// Поддерживает:
/// - GGUF модели
/// - iOS 18+ iPhone and iPad devices that meet the model memory budget
/// - Metal acceleration
actor LlamaEngine: LocalInferenceEngine {

    // MARK: - Properties

    private var context: LlamaContext?
    private var config: ModelConfig?
    private var currentModelPath: String?

    var modelInfo: LoadedModelInfo? {
        guard let modelPath = currentModelPath,
              let config = config,
              context != nil else {
            return nil
        }

        return LoadedModelInfo(
            modelId: modelPath.components(separatedBy: "/").last ?? "unknown",
            contextSize: config.contextSize,
            vocabularySize: 0, // Will be determined when full llama.cpp is integrated
            engineType: .llama,
            modelPath: modelPath,
            usesMetal: config.useMetal
        )
    }

    // MARK: - Initialization

    init() {
        Logger.shared.info("🦙 LlamaEngine initialized")
    }

    // MARK: - LocalInferenceEngine Protocol

    func loadModel(modelPath: String, config: ModelConfig) async throws {
        Logger.shared.info("🔄 Loading GGUF model from: \(modelPath)")

        // Validate model file exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            Logger.shared.error("❌ Model file not found: \(modelPath)")
            throw InferenceEngineError.invalidModelPath(modelPath)
        }

        // Verify it's a GGUF file
        guard modelPath.hasSuffix(".gguf") else {
            Logger.shared.error("❌ Not a GGUF file: \(modelPath)")
            throw InferenceEngineError.invalidFormat(expected: "GGUF", got: "Unknown")
        }

        do {
            // Create llama context
            let llamaContext = LlamaContext(
                modelPath: modelPath,
                config: config
            )

            // Load the model
            try await llamaContext.loadModel()

            // Store state
            self.context = llamaContext
            self.config = config
            self.currentModelPath = modelPath

            Logger.shared.info("✅ GGUF model loaded successfully")
            Logger.shared.info("📊 Context size: \(config.contextSize) tokens")
            Logger.shared.info("🔧 Metal: \(config.useMetal ? "Enabled" : "Disabled")")

        } catch {
            Logger.shared.error("❌ Failed to load model: \(error.localizedDescription)")
            throw InferenceEngineError.loadFailed(error.localizedDescription)
        }
    }

    func generate(
        prompt: LocalRenderedPrompt,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let context = context else {
            Logger.shared.error("❌ Model not loaded")
            throw InferenceEngineError.modelNotLoaded
        }

        Logger.shared.info("🚀 Starting generation with llama.cpp")
        Logger.shared.info("📝 Prompt length: \(prompt.text.count) characters")
        Logger.shared.info("⚙️ Max tokens: \(prompt.options.maxTokens), Temperature: \(prompt.options.temperature), TopP: \(prompt.options.topP)")

        do {
            try await context.generate(
                prompt: prompt,
                onToken: onToken
            )

            Logger.shared.info("✅ Generation complete")

        } catch {
            Logger.shared.error("❌ Generation failed: \(error.localizedDescription)")
            throw InferenceEngineError.generationFailed(error.localizedDescription)
        }
    }

    func cleanup() async {
        Logger.shared.info("🧹 Cleaning up LlamaEngine resources...")

        if let context = context {
            await context.cleanup()
        }

        self.context = nil
        self.config = nil
        self.currentModelPath = nil

        Logger.shared.info("✅ LlamaEngine cleanup complete")
    }
}
