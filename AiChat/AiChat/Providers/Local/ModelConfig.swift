import Foundation

/// Конфигурация для загрузки и работы с локальной моделью
struct ModelConfig {
    /// Размер контекста (количество токенов)
    let contextSize: Int

    /// Использовать Metal (GPU) для ускорения
    let useMetal: Bool

    /// Количество слоев на GPU (-1 = все слои)
    let gpuLayers: Int

    /// Размер batch для обработки токенов
    let batchSize: Int

    /// Размер GPU cache (только для MLX, в байтах)
    let gpuCacheLimit: Int?

    /// Количество потоков (только для llama.cpp)
    let threads: Int?

    // MARK: - Presets

    /// Дефолтная конфигурация
    static var `default`: ModelConfig {
        ModelConfig(
            contextSize: 2048,
            useMetal: true,
            gpuLayers: -1,
            batchSize: 512,
            gpuCacheLimit: nil,
            threads: nil
        )
    }

    /// Оптимизированная конфигурация для MLX
    /// - Parameter deviceRAM: RAM устройства в байтах
    static func mlxOptimized(deviceRAM: UInt64) -> ModelConfig {
        let gpuCache = DeviceCapabilities.recommendedGPUCacheSize

        // Больше RAM = больше контекст
        let contextSize: Int
        let memoryMB = Int(deviceRAM / 1_048_576)
        if memoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 12) {
            contextSize = 4096  // 12GB+
        } else if memoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 8) {
            contextSize = 2048  // 8GB+
        } else {
            contextSize = 1024  // < 8GB (не должно быть для MLX)
        }

        return ModelConfig(
            contextSize: contextSize,
            useMetal: true,
            gpuLayers: -1,
            batchSize: 512,
            gpuCacheLimit: gpuCache,
            threads: nil
        )
    }

    /// Оптимизированная конфигурация для llama.cpp
    /// - Parameter deviceRAM: RAM устройства в байтах
    static func llamaOptimized(deviceRAM: UInt64, modelSizeBytes: UInt64? = nil) -> ModelConfig {
        let threads = ProcessInfo.processInfo.processorCount

        let contextSize: Int
        let batchSize: Int
        let memoryMB = Int(deviceRAM / 1_048_576)
        if memoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 8) {
            contextSize = 1024  // 8GB+
            batchSize = 64
        } else if memoryMB >= DeviceCapabilityProfile.minimumPhysicalMemoryMB(forNominalGB: 6) {
            contextSize = 768   // 6GB+
            batchSize = 32
        } else {
            contextSize = 512   // < 6GB
            batchSize = 16
        }

        var effectiveContextSize = contextSize
        var effectiveBatchSize = batchSize
        if let modelSizeBytes {
            let modelSizeGB = Double(modelSizeBytes) / 1_073_741_824.0
            if modelSizeGB >= 1.5 {
                effectiveContextSize = min(effectiveContextSize, 512)
                effectiveBatchSize = min(effectiveBatchSize, 16)
            }
            if modelSizeGB >= 2.3 {
                effectiveContextSize = min(effectiveContextSize, 384)
                effectiveBatchSize = min(effectiveBatchSize, 8)
            }
        }

        return ModelConfig(
            contextSize: effectiveContextSize,
            useMetal: true,
            gpuLayers: -1,  // Все слои на GPU если возможно
            batchSize: effectiveBatchSize,
            gpuCacheLimit: nil,
            threads: threads
        )
    }

    /// Конфигурация для тестирования (минимальные ресурсы)
    static var testing: ModelConfig {
        ModelConfig(
            contextSize: 512,
            useMetal: true,
            gpuLayers: -1,
            batchSize: 64,
            gpuCacheLimit: 256 * 1024 * 1024, // 256MB
            threads: 2
        )
    }

    /// Конфигурация для максимальной производительности (требует много RAM)
    static var performance: ModelConfig {
        ModelConfig(
            contextSize: 8192,
            useMetal: true,
            gpuLayers: -1,
            batchSize: 1024,
            gpuCacheLimit: 2048 * 1024 * 1024, // 2GB
            threads: ProcessInfo.processInfo.processorCount
        )
    }
}

// MARK: - CustomStringConvertible

extension ModelConfig: CustomStringConvertible {
    var description: String {
        """
        ModelConfig(
          contextSize: \(contextSize)
          useMetal: \(useMetal)
          gpuLayers: \(gpuLayers)
          batchSize: \(batchSize)
          gpuCacheLimit: \(gpuCacheLimit.map { "\($0 / 1024 / 1024)MB" } ?? "nil")
          threads: \(threads.map { "\($0)" } ?? "nil")
        )
        """
    }
}
