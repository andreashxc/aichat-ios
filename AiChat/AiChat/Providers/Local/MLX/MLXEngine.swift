import Foundation

// MLX imports - only available on real devices, not simulator
#if canImport(MLX) && !targetEnvironment(simulator)
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
#endif

/// MLX-based inference engine for real iPhone and iPad devices.
///
/// Requires:
/// - iOS 18.0+
/// - At least 7,500 MB physical memory
/// - MLX package available for the target platform
@available(iOS 18.0, *)
actor MLXEngine: LocalInferenceEngine {

    // MARK: - Properties

    #if canImport(MLX) && !targetEnvironment(simulator)
    private var modelContainer: ModelContainer?
    #endif

    private var config: ModelConfig?
    private var modelPath: String?
    private var isModelLoaded: Bool = false

    var modelInfo: LoadedModelInfo? {
        guard let modelPath = modelPath,
              let config = config,
              isModelLoaded else {
            return nil
        }

        return LoadedModelInfo(
            modelId: modelPath.components(separatedBy: "/").last ?? "unknown",
            contextSize: config.contextSize,
            vocabularySize: 0, // Will be determined when loading
            engineType: .mlx,
            modelPath: modelPath,
            usesMetal: config.useMetal
        )
    }

    // MARK: - Initialization

    init() {
        Logger.shared.info("🚀 MLXEngine initialized")
    }

    // MARK: - LocalInferenceEngine Protocol

    func loadModel(modelPath: String, config: ModelConfig) async throws {
        #if canImport(MLX) && !targetEnvironment(simulator)
        Logger.shared.info("🔄 Loading MLX model from: \(modelPath)")

        // Validate model path exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            Logger.shared.error("❌ Model directory not found: \(modelPath)")
            throw InferenceEngineError.invalidModelPath(modelPath)
        }

        do {
            // Configure GPU cache
            if let gpuCacheLimit = config.gpuCacheLimit {
                let cacheMB = gpuCacheLimit / 1024 / 1024
                Logger.shared.info("⚙️ Setting GPU cache limit: \(cacheMB)MB")
                MLX.GPU.set(cacheLimit: gpuCacheLimit)
            }

            // Verify model files exist
            let modelURL = URL(fileURLWithPath: modelPath)
            let configPath = modelURL.appendingPathComponent("config.json").path

            guard FileManager.default.fileExists(atPath: configPath) else {
                Logger.shared.error("❌ config.json not found in model directory")
                throw InferenceEngineError.loadFailed("config.json not found")
            }

            // Check for model weights and completeness
            let contents = try FileManager.default.contentsOfDirectory(atPath: modelPath)
            let hasWeights = contents.contains { $0.hasSuffix(".safetensors") }

            guard hasWeights else {
                Logger.shared.error("❌ No .safetensors weights found")
                throw InferenceEngineError.loadFailed("No .safetensors weights found. MLX requires safetensors format.")
            }

            let modelId = URL(fileURLWithPath: modelPath).lastPathComponent
            let storage = ModelStorage()
            guard storage.isMLXModelComplete(modelId: modelId) else {
                Logger.shared.error("❌ MLX model files incomplete or corrupted")
                throw InferenceEngineError.loadFailed("MLX model files are incomplete. Please re-download the model.")
            }

            Logger.shared.info("✅ Model files validated")
            Logger.shared.info("📦 Found files: \(contents.joined(separator: ", "))")

            // Load model using MLX LLM
            Logger.shared.info("⏳ Loading MLX model...")

            let configuration = ModelConfiguration(
                directory: modelURL,
                extraEOSTokens: Set(Self.inferStopTokens(from: modelPath))
            )

            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { progress in
                if progress.fractionCompleted > 0 {
                    Logger.shared.info("📥 Loading: \(Int(progress.fractionCompleted * 100))%")
                }
            }

            Logger.shared.info("✅ MLX model loaded successfully!")

            // Store state
            self.modelContainer = container
            self.config = config
            self.modelPath = modelPath
            self.isModelLoaded = true

        } catch {
            Logger.shared.error("❌ Failed to load MLX model: \(error.localizedDescription)")
            throw InferenceEngineError.loadFailed(error.localizedDescription)
        }
        #else
        Logger.shared.error("❌ MLX framework not available")
        throw InferenceEngineError.unsupportedDevice
        #endif
    }

    func generate(
        prompt: LocalRenderedPrompt,
        onToken: @escaping (String) -> Void
    ) async throws {
        #if canImport(MLX) && !targetEnvironment(simulator)
        guard isModelLoaded, let container = modelContainer else {
            Logger.shared.error("❌ Model not loaded")
            throw InferenceEngineError.modelNotLoaded
        }

        Logger.shared.info("🚀 Starting MLX generation")
        Logger.shared.info("📝 Prompt length: \(prompt.text.count) characters")
        Logger.shared.info("⚙️ Max tokens: \(prompt.options.maxTokens), Temperature: \(prompt.options.temperature), TopP: \(prompt.options.topP)")

        do {
            try await container.perform { context in
                // Create generation parameters
                let parameters = GenerateParameters(
                    maxTokens: prompt.options.maxTokens,
                    temperature: prompt.options.temperature,
                    topP: prompt.options.topP
                )

                // Prepare input
                let userInput = UserInput(prompt: prompt.text)
                let input = try await context.processor.prepare(input: userInput)

                // Create cache
                let cache = context.model.newCache(parameters: parameters)

                var stopFilter = LocalStopTokenStreamFilter(stopTokens: prompt.options.stopTokens)

                // Generate with streaming
                for try await item in try MLXLMCommon.generate(
                    input: input,
                    cache: cache,
                    parameters: parameters,
                    context: context
                ) {
                    switch item {
                    case .chunk(let string):
                        let filtered = stopFilter.consume(string)
                        if !filtered.output.isEmpty {
                            onToken(filtered.output)
                        }
                        if filtered.didStop {
                            return
                        }
                    case .info(let info):
                        Logger.shared.info("📊 \(info.tokensPerSecond.formatted()) tokens/sec")
                    case .toolCall:
                        break
                    }
                }

                let remainder = stopFilter.finish()
                if !remainder.isEmpty {
                    onToken(remainder)
                }
            }

            Logger.shared.info("✅ MLX generation complete")

        } catch {
            Logger.shared.error("❌ Generation failed: \(error.localizedDescription)")
            throw InferenceEngineError.generationFailed(error.localizedDescription)
        }

        #else
        Logger.shared.error("❌ MLX framework not available")
        throw InferenceEngineError.unsupportedDevice
        #endif
    }

    func cleanup() async {
        Logger.shared.info("🧹 Cleaning up MLX resources...")

        #if canImport(MLX) && !targetEnvironment(simulator)
        // Clear GPU cache
        MLX.GPU.clearCache()
        self.modelContainer = nil
        #endif

        self.config = nil
        self.modelPath = nil
        self.isModelLoaded = false

        Logger.shared.info("✅ Cleanup complete")
    }

    private static func inferStopTokens(from modelPath: String) -> [String] {
        let name = URL(fileURLWithPath: modelPath).lastPathComponent.lowercased()

        if name.contains("qwen") {
            return ["<|im_end|>", "<|endoftext|>"]
        }
        if name.contains("gemma") {
            return ["<end_of_turn>", "<eos>", "</s>"]
        }
        if name.contains("llama-3") || name.contains("llama3") {
            return ["<|eot_id|>", "</s>"]
        }
        return ["</s>"]
    }
}
