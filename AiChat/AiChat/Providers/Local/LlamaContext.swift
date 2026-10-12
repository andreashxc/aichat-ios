import Foundation
import SwiftLlama

/// Helper to run a throwing closure on SwiftLlamaActor (same executor used by SwiftLlama.start(for:))
@SwiftLlamaActor
private func makeLlamaInstance(path: String, config: Configuration) throws -> SwiftLlama {
    try SwiftLlama(modelPath: path, modelConfiguration: config)
}

/// Swift wrapper for llama.cpp inference using SwiftLlama
/// Provides GGUF model loading and streaming text generation
actor LlamaContext {
    private var modelPath: String
    private var contextSize: Int
    private var batchSize: Int
    private var llamaInstance: SwiftLlama?
    private var activeConfigurationKey: ConfigurationKey?

    init(modelPath: String, config: ModelConfig = .default) {
        self.modelPath = modelPath
        self.contextSize = config.contextSize
        self.batchSize = config.batchSize
    }

    /// Load the GGUF model from disk
    func loadModel() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LlamaError.modelNotFound(path: modelPath)
        }

        Logger.shared.info("📂 Loading GGUF model from: \(modelPath)")

        do {
            try await configureLlamaInstance(
                options: LocalGenerationOptions(
                    profile: LocalGenerationProfile(
                        temperature: 0.7,
                        maxTokens: 512,
                        topP: 0.9,
                        topK: 40,
                        presencePenalty: 0,
                        thinkingMode: .automatic
                    ),
                    stopTokens: inferStopTokens(from: modelPath)
                ),
                promptCharacterCount: 0
            )

            Logger.shared.info("✅ GGUF model loaded successfully via SwiftLlama")
            Logger.shared.info("📊 SwiftLlama config: n_ctx=\(contextSize), batch=\(batchSize)")
        } catch {
            Logger.shared.error("❌ Failed to load model: \(error.localizedDescription)")
            throw LlamaError.loadFailed(reason: error.localizedDescription)
        }
    }

    /// Generate text from a prompt with streaming
    func generate(
        prompt: LocalRenderedPrompt,
        onToken: @escaping (String) -> Void
    ) async throws {
        let llamaPrompt = try makeSwiftLlamaPrompt(from: prompt)
        try await configureLlamaInstance(
            options: prompt.options,
            promptCharacterCount: prompt.text.count
        )

        Logger.shared.info("🚀 Starting generation with llama.cpp")
        Logger.shared.info("⚙️ Max tokens: \(prompt.options.maxTokens), Temperature: \(prompt.options.temperature), TopP: \(prompt.options.topP)")

        do {
            guard let llama = llamaInstance else {
                Logger.shared.error("❌ Model not loaded")
                throw LlamaError.generationFailed(reason: "Model not loaded. Call loadModel() first.")
            }


            // start(for:) is @SwiftLlamaActor — all C++ inference runs on that actor
            var emittedTokenCount = 0
            for try await token in await llama.start(for: llamaPrompt) {
                guard emittedTokenCount < prompt.options.maxTokens else {
                    Logger.shared.info("🛑 Stopped after local maxTokens budget: \(prompt.options.maxTokens)")
                    break
                }
                emittedTokenCount += 1
                onToken(token)
            }

            Logger.shared.info("✅ Generation complete via SwiftLlama")

        } catch let error as NSError {
            Logger.shared.error("❌ Generation failed: \(error)")
            Logger.shared.error("   Domain: \(error.domain)")
            Logger.shared.error("   Code: \(error.code)")
            Logger.shared.error("   Description: \(error.localizedDescription)")
            throw LlamaError.generationFailed(reason: error.localizedDescription)
        } catch {
            Logger.shared.error("❌ Generation failed: \(error.localizedDescription)")
            throw LlamaError.generationFailed(reason: error.localizedDescription)
        }
    }

    private struct ConfigurationKey: Hashable {
        let temperature: Float
        let topP: Float
        let topK: Int
        let maxTokenCount: Int
        let stopTokens: [String]
    }

    private func configureLlamaInstance(
        options: LocalGenerationOptions,
        promptCharacterCount: Int
    ) async throws {
        let maxTokenCount = swiftLlamaMaxTokenCount(
            requestedNewTokens: options.maxTokens,
            promptCharacterCount: promptCharacterCount
        )
        let key = ConfigurationKey(
            temperature: options.temperature,
            topP: options.topP,
            topK: options.topK,
            maxTokenCount: maxTokenCount,
            stopTokens: options.stopTokens
        )

        guard llamaInstance == nil || activeConfigurationKey != key else {
            return
        }

        if let oldKey = activeConfigurationKey, oldKey.topP != key.topP {
            Logger.shared.info("⚠️ Reinitializing SwiftLlama to apply topP. SwiftLlama 0.4.0 stores topP in Configuration, but its sampler currently applies temperature only.")
        }

        let config = Configuration(
            topK: options.topK,
            topP: options.topP,
            nCTX: contextSize,
            temperature: options.temperature,
            batchSize: batchSize,
            maxTokenCount: maxTokenCount,
            stopTokens: options.stopTokens
        )

        let llama = try await makeLlamaInstance(path: modelPath, config: config)
        self.llamaInstance = llama
        self.activeConfigurationKey = key

        Logger.shared.info("📊 SwiftLlama generation config: n_ctx=\(contextSize), batch=\(batchSize), maxTokenCount=\(maxTokenCount), temperature=\(options.temperature), topP=\(options.topP), topK=\(options.topK), stops=\(options.stopTokens)")
    }

    private func swiftLlamaMaxTokenCount(
        requestedNewTokens: Int,
        promptCharacterCount: Int
    ) -> Int {
        let estimatedPromptTokens = max(1, promptCharacterCount / 4)
        return min(contextSize, max(128, estimatedPromptTokens + requestedNewTokens))
    }

    private func makeSwiftLlamaPrompt(from renderedPrompt: LocalRenderedPrompt) throws -> Prompt {
        guard let prompt = renderedPrompt.swiftLlamaPrompt else {
            throw LlamaError.generationFailed(reason: "SwiftLlama prompt fields were not rendered.")
        }

        return Prompt(
            type: promptType(from: prompt.kind),
            systemPrompt: prompt.systemPrompt.isEmpty ? "You are a helpful AI assistant." : prompt.systemPrompt,
            userMessage: prompt.userMessage,
            history: prompt.history.map { Chat(user: $0.user, bot: $0.assistant) }
        )
    }

    private func promptType(from kind: LocalSwiftLlamaPromptKind) -> Prompt.`Type` {
        switch kind {
        case .chatML:
            return .chatML
        case .llama:
            return .llama
        case .llama3:
            return .llama3
        case .mistral:
            return .mistral
        case .phi:
            return .phi
        case .gemma:
            return .gemma
        }
    }

    /// Model-specific stop tokens to prevent infinite generation
    private func inferStopTokens(from modelPath: String) -> [String] {
        let name = URL(fileURLWithPath: modelPath).lastPathComponent.lowercased()

        if name.contains("qwen") {
            return ["<|im_end|>", "<|endoftext|>"]
        }
        if name.contains("llama-3") || name.contains("llama3") {
            return ["<|eot_id|>"]
        }
        if name.contains("gemma") {
            return ["<end_of_turn>"]
        }
        if name.contains("phi") {
            return ["<|end|>"]
        }
        return ["</s>"]
    }

    /// Clean up resources
    func cleanup() {
        Logger.shared.info("🧹 Cleaning up LlamaContext")
        llamaInstance = nil
        activeConfigurationKey = nil
    }
}

enum LlamaError: Error, LocalizedError {
    case modelNotFound(path: String)
    case loadFailed(reason: String)
    case generationFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model file not found at: \(path)"
        case .loadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}
