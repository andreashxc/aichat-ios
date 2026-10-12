import Foundation

struct ModelStorage {
    let fileManager: FileManager
    private let modelsDirectoryOverride: URL?

    init(fileManager: FileManager = .default, modelsDirectoryOverride: URL? = nil) {
        self.fileManager = fileManager
        self.modelsDirectoryOverride = modelsDirectoryOverride
    }

    var modelsDirectory: URL {
        let dir: URL
        if let modelsDirectoryOverride {
            dir = modelsDirectoryOverride
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dir = base.appendingPathComponent("Models", isDirectory: true)
        }

        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                Logger.shared.info("Created models directory at: \(dir.path)")
            } catch {
                Logger.shared.error("Failed to create models directory: \(error.localizedDescription)")
            }
        }
        return dir
    }

    // MARK: - Model Path Resolution

    func fileURL(for descriptor: LocalModelDescriptor) -> URL {
        modelsDirectory.appendingPathComponent(descriptor.filename)
    }

    /// Get the path for a model (file for GGUF, directory for MLX)
    func fileURL(for modelId: String) -> URL {
        // Try MLX directory first
        let mlxDir = modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
        if fileManager.fileExists(atPath: mlxDir.path) {
            return mlxDir
        }

        // Fall back to GGUF file
        return modelsDirectory.appendingPathComponent("\(modelId).gguf")
    }

    /// Get the model path specifically for a format
    func fileURL(for modelId: String, format: ModelFormat) -> URL {
        switch format {
        case .gguf:
            return modelsDirectory.appendingPathComponent("\(modelId).gguf")
        case .mlx:
            return modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
        }
    }

    // MARK: - Format Detection

    /// Detect the format of a model based on what exists on disk
    func detectFormat(for modelId: String) -> ModelFormat? {
        // Check for MLX directory
        let mlxDir = modelsDirectory.appendingPathComponent(modelId, isDirectory: true)
        if fileManager.fileExists(atPath: mlxDir.path) {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: mlxDir.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                return .mlx
            }
        }

        // Check for GGUF file
        let ggufFile = modelsDirectory.appendingPathComponent("\(modelId).gguf")
        if fileManager.fileExists(atPath: ggufFile.path) {
            return .gguf
        }

        return nil
    }

    // MARK: - Save Operations

    /// Save a GGUF model (single file)
    func saveModel(from temporaryURL: URL, modelId: String, filename: String) throws {
        // Ensure directory exists before saving
        let directory = modelsDirectory
        Logger.shared.info("Models directory: \(directory.path)")
        Logger.shared.info("Directory exists: \(fileManager.fileExists(atPath: directory.path))")

        // Ensure the directory was created successfully
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            Logger.shared.info("Created models directory during save")
        }

        let destinationURL = directory.appendingPathComponent(filename)
        Logger.shared.info("Destination URL: \(destinationURL.path)")
        Logger.shared.info("Temporary file exists: \(fileManager.fileExists(atPath: temporaryURL.path))")

        // Check temp file size BEFORE moving
        if let tempAttributes = try? fileManager.attributesOfItem(atPath: temporaryURL.path),
           let tempSize = tempAttributes[.size] as? Int64 {
            let tempSizeMB = Double(tempSize) / 1024.0 / 1024.0
            Logger.shared.info("📦 Temp file size BEFORE move: \(String(format: "%.2f", tempSizeMB)) MB")
        } else {
            Logger.shared.error("❌ Could not get temp file attributes!")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
            Logger.shared.info("Removed existing file at destination")
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        Logger.shared.info("Model saved to: \(destinationURL.path)")

        // Check destination file size AFTER moving
        if let destAttributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
           let destSize = destAttributes[.size] as? Int64 {
            let destSizeMB = Double(destSize) / 1024.0 / 1024.0
            Logger.shared.info("📦 Destination file size AFTER move: \(String(format: "%.2f", destSizeMB)) MB")
        } else {
            Logger.shared.error("❌ Could not get destination file attributes!")
        }
    }

    /// Save an MLX model file to the model directory
    func saveMLXFile(from temporaryURL: URL, modelId: String, filename: String) throws {
        let modelDir = fileURL(for: modelId, format: .mlx)

        // Create model directory if it doesn't exist
        if !fileManager.fileExists(atPath: modelDir.path) {
            try fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
            Logger.shared.info("📁 Created MLX model directory: \(modelDir.path)")
        }

        let destinationURL = modelDir.appendingPathComponent(filename)
        Logger.shared.info("📥 Saving MLX file: \(filename) to \(destinationURL.path)")

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
            Logger.shared.info("🗑️ Removed existing file at destination")
        }

        // Move file to destination
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        Logger.shared.info("✅ MLX file saved: \(filename)")
    }

    // MARK: - Delete Operations

    func deleteModel(modelId: String) throws {
        // Try to detect format first
        if let format = detectFormat(for: modelId) {
            let fileURL = self.fileURL(for: modelId, format: format)

            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
                Logger.shared.info("Model deleted: \(modelId) (format: \(format.rawValue))")
                return
            }
        }

        // Fallback: try both formats
        let ggufURL = self.fileURL(for: modelId, format: .gguf)
        let mlxURL = self.fileURL(for: modelId, format: .mlx)

        if fileManager.fileExists(atPath: ggufURL.path) {
            try fileManager.removeItem(at: ggufURL)
            Logger.shared.info("Model deleted: \(modelId) (GGUF)")
        }

        if fileManager.fileExists(atPath: mlxURL.path) {
            try fileManager.removeItem(at: mlxURL)
            Logger.shared.info("Model deleted: \(modelId) (MLX)")
        }
    }

    // MARK: - Existence Checks

    func modelExists(modelId: String) -> Bool {
        // Check both formats
        let ggufURL = self.fileURL(for: modelId, format: .gguf)
        let mlxURL = self.fileURL(for: modelId, format: .mlx)

        return fileManager.fileExists(atPath: ggufURL.path) ||
               fileManager.fileExists(atPath: mlxURL.path)
    }

    /// Check if an MLX model is complete (has all required files)
    func isMLXModelComplete(modelId: String) -> Bool {
        let modelDir = fileURL(for: modelId, format: .mlx)

        guard fileManager.fileExists(atPath: modelDir.path) else {
            return false
        }

        func fileSize(at url: URL) -> Int64? {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? Int64 else {
                return nil
            }
            return size
        }

        // Required files for MLX models
        let requiredFiles = ["config.json", "tokenizer.json"]

        // Check all required files exist
        for file in requiredFiles {
            let fileURL = modelDir.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                Logger.shared.info("❌ Missing required MLX file: \(file)")
                return false
            }
            if let size = fileSize(at: fileURL), size == 0 {
                Logger.shared.info("❌ Required MLX file is empty: \(file)")
                return false
            }
        }

        let indexURL = modelDir.appendingPathComponent("model.safetensors.index.json")
        let hasIndex = fileManager.fileExists(atPath: indexURL.path)

        // If there's an index file, this is a sharded model - verify all shards exist
        if hasIndex {
            Logger.shared.info("📦 Detected sharded MLX model, validating shards...")

            // Parse index to get required shard files
            guard let indexData = try? Data(contentsOf: indexURL),
                  let indexJson = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any],
                  let weightMap = indexJson["weight_map"] as? [String: String] else {
                Logger.shared.info("❌ Failed to parse model.safetensors.index.json")
                return false
            }

            // Get unique shard files from weight_map
            let requiredShards = Set(weightMap.values)
            Logger.shared.info("📋 Required shards: \(requiredShards.sorted().joined(separator: ", "))")

            for shard in requiredShards {
                let shardURL = modelDir.appendingPathComponent(shard)
                guard fileManager.fileExists(atPath: shardURL.path) else {
                    Logger.shared.info("❌ Missing shard file: \(shard)")
                    return false
                }
                if let size = fileSize(at: shardURL), size == 0 {
                    Logger.shared.info("❌ Shard file is empty: \(shard)")
                    return false
                }
            }

            Logger.shared.info("✅ All \(requiredShards.count) shards validated")
        } else {
            // Non-sharded model - check for single weight file
            let weightFiles = ["weights.safetensors", "model.safetensors"]
            let hasWeights = weightFiles.contains { file in
                let fileURL = modelDir.appendingPathComponent(file)
                if fileManager.fileExists(atPath: fileURL.path) {
                    if let size = fileSize(at: fileURL), size > 0 {
                        return true
                    }
                }
                return false
            }

            if !hasWeights {
                Logger.shared.info("❌ Missing MLX weight files (no index, no weights)")
                return false
            }
        }

        Logger.shared.info("✅ MLX model is complete: \(modelId)")
        return true
    }

    /// Get the list of files in an MLX model directory
    func getMLXModelFiles(modelId: String) -> [String] {
        let modelDir = fileURL(for: modelId, format: .mlx)

        guard let contents = try? fileManager.contentsOfDirectory(atPath: modelDir.path) else {
            return []
        }

        return contents.sorted()
    }

    // MARK: - Size Calculations

    func getModelSize(modelId: String) -> Int64? {
        guard let format = detectFormat(for: modelId) else {
            return nil
        }

        let fileURL = self.fileURL(for: modelId, format: format)

        switch format {
        case .gguf:
            // Single file
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let size = attributes[.size] as? Int64 else {
                return nil
            }
            return size

        case .mlx:
            // Sum all files in directory
            guard let contents = try? fileManager.contentsOfDirectory(atPath: fileURL.path) else {
                return nil
            }

            var totalSize: Int64 = 0
            for file in contents {
                let filePath = fileURL.appendingPathComponent(file).path
                if let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                   let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }

            return totalSize
        }
    }
}
