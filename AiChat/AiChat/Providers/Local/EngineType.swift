import Foundation

/// Local inference backend.
enum EngineType: String, Codable, CaseIterable, Sendable {
    /// MLX Swift optimized for high-memory Apple devices.
    case mlx = "MLX"

    /// llama.cpp / SwiftLlama GGUF runtime.
    case llama = "llama.cpp"

    // MARK: - Display Properties

    /// Отображаемое имя
    var displayName: String {
        switch self {
        case .mlx:
            return "MLX Swift"
        case .llama:
            return "llama.cpp"
        }
    }

    /// Полное описание
    var description: String {
        switch self {
        case .mlx:
            return "Optimized for iOS 18+ real devices with at least 7,500 MB physical memory"
        case .llama:
            return "GGUF runtime for iOS 18+ iPhone and iPad devices"
        }
    }

    /// SF Symbol иконка
    var icon: String {
        switch self {
        case .mlx:
            return "cpu.fill"  // Apple Silicon
        case .llama:
            return "cpu"       // Универсальный процессор
        }
    }

    // MARK: - Technical Properties

    /// Формат модели для этого engine
    var modelFormat: ModelFormat {
        switch self {
        case .mlx:
            return .mlx
        case .llama:
            return .gguf
        }
    }

    /// Минимальная версия iOS
    var minimumIOSVersion: Double {
        switch self {
        case .mlx:
            return 18.0
        case .llama:
            return 18.0
        }
    }

    // MARK: - Performance Characteristics

    /// Относительная производительность (1.0 = baseline)
    var performanceMultiplier: Double {
        switch self {
        case .mlx:
            return 2.5  // MLX ~2-3x быстрее на Apple Silicon
        case .llama:
            return 1.0  // Baseline
        }
    }

    /// Эффективность использования памяти (1.0 = baseline)
    var memoryEfficiency: Double {
        switch self {
        case .mlx:
            return 1.2  // MLX более эффективен с unified memory
        case .llama:
            return 1.0  // Baseline
        }
    }
}

// MARK: - ModelFormat

/// Формат файлов модели
enum ModelFormat: String, Codable, Sendable {
    /// GGUF - формат llama.cpp (один файл)
    case gguf = "GGUF"

    /// MLX - формат Apple MLX (директория с несколькими файлами)
    case mlx = "MLX"

    /// Расширение файла (для GGUF)
    var fileExtension: String {
        switch self {
        case .gguf:
            return "gguf"
        case .mlx:
            return ""  // MLX использует директорию
        }
    }

    /// Использует директорию вместо одного файла
    var isDirectory: Bool {
        switch self {
        case .gguf:
            return false
        case .mlx:
            return true
        }
    }

    /// Типичные файлы в формате
    var requiredFiles: [String] {
        switch self {
        case .gguf:
            return ["*.gguf"]
        case .mlx:
            return ["config.json", "*.safetensors", "tokenizer.json"]
        }
    }
}
