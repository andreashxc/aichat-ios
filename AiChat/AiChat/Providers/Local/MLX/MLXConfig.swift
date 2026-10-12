import Foundation

// MLX imports - only available on real devices, not simulator
#if canImport(MLX) && !targetEnvironment(simulator)
import MLX
#endif

/// Configuration specific to MLX engine
@available(iOS 18.0, *)
struct MLXConfiguration {

    /// Model loading configuration
    struct ModelLoadConfiguration {
        /// Model directory path
        let modelPath: String

        /// GPU cache limit in bytes
        let gpuCacheLimit: Int

        /// Whether to use quantization
        let useQuantization: Bool

        init(
            modelPath: String,
            gpuCacheLimit: Int = DeviceCapabilities.recommendedGPUCacheSize,
            useQuantization: Bool = true
        ) {
            self.modelPath = modelPath
            self.gpuCacheLimit = gpuCacheLimit
            self.useQuantization = useQuantization
        }
    }

    /// Generation parameters for MLX
    struct GenerationParameters {
        /// Temperature for sampling (0.0 - 2.0)
        let temperature: Float

        /// Top-p (nucleus) sampling parameter
        let topP: Float

        /// Repetition penalty
        let repetitionPenalty: Float

        /// Maximum number of tokens to generate
        let maxTokens: Int

        /// Top-k sampling parameter
        let topK: Int?

        init(
            temperature: Float = 0.7,
            topP: Float = 0.95,
            repetitionPenalty: Float = 1.1,
            maxTokens: Int = 512,
            topK: Int? = nil
        ) {
            self.temperature = temperature
            self.topP = topP
            self.repetitionPenalty = repetitionPenalty
            self.maxTokens = maxTokens
            self.topK = topK
        }

        /// Create from ModelConfig
        static func from(_ config: ModelConfig, maxTokens: Int, temperature: Float) -> GenerationParameters {
            return GenerationParameters(
                temperature: temperature,
                topP: 0.95,
                repetitionPenalty: 1.1,
                maxTokens: maxTokens,
                topK: nil
            )
        }
    }

    // MARK: - Presets

    /// Balanced preset - good for most use cases
    static func balanced(modelPath: String) -> ModelLoadConfiguration {
        ModelLoadConfiguration(
            modelPath: modelPath,
            gpuCacheLimit: DeviceCapabilities.recommendedGPUCacheSize,
            useQuantization: true
        )
    }

    /// Performance preset - maximum speed
    static func performance(modelPath: String) -> ModelLoadConfiguration {
        let memoryMB = DeviceCapabilities.deviceRAMInMB()
        let largeCache = memoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 12)
            ? 2048 * 1024 * 1024  // 2GB for 12GB+ devices
            : 1024 * 1024 * 1024   // 1GB for 8GB devices

        return ModelLoadConfiguration(
            modelPath: modelPath,
            gpuCacheLimit: largeCache,
            useQuantization: true
        )
    }

    /// Memory-efficient preset - lower memory usage
    static func memoryEfficient(modelPath: String) -> ModelLoadConfiguration {
        ModelLoadConfiguration(
            modelPath: modelPath,
            gpuCacheLimit: 256 * 1024 * 1024,  // 256MB
            useQuantization: true
        )
    }
}
