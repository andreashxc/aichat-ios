import Foundation

@MainActor
enum AttachmentStore {
    private static let directoryName = "ChatAttachments"
    static var attachmentDirectoryOverride: URL?

    static func saveImageData(_ data: Data, fileExtension: String = "jpg") -> String? {
        guard let folderURL = attachmentDirectoryURL(createIfNeeded: true) else { return nil }

        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let fileURL = folderURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: [.atomic])
            return fileURL.path
        } catch {
            Logger.shared.error("Failed to save attachment: \(error.localizedDescription)")
            return nil
        }
    }

    static func saveAudioData(_ data: Data, fileExtension: String) -> String? {
        guard let folderURL = attachmentDirectoryURL(createIfNeeded: true) else { return nil }

        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let fileURL = folderURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: [.atomic])
            return fileURL.path
        } catch {
            Logger.shared.error("Failed to save attachment: \(error.localizedDescription)")
            return nil
        }
    }

    static func mimeType(forFileExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "m4a":
            return "audio/m4a"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "caf":
            return "audio/x-caf"
        case "aac":
            return "audio/aac"
        default:
            return "application/octet-stream"
        }
    }

    @discardableResult
    static func deleteFile(path: String) -> Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return 0 }

        let reclaimedBytes = fileSize(path: path)
        do {
            try fileManager.removeItem(atPath: path)
            return reclaimedBytes
        } catch {
            Logger.shared.error("Failed to delete attachment file: \(error.localizedDescription)")
            return 0
        }
    }

    @discardableResult
    static func deleteFiles(paths: [String]) -> Int64 {
        paths.reduce(Int64(0)) { total, path in
            total + deleteFile(path: path)
        }
    }

    @discardableResult
    static func deleteAttachments(for messages: [ChatMessage]) -> Int64 {
        deleteFiles(paths: attachmentPaths(in: messages))
    }

    @discardableResult
    static func cleanupOrphanedAttachments(existingMessages: [ChatMessage]) -> Int64 {
        guard let folderURL = attachmentDirectoryURL(createIfNeeded: false) else { return 0 }

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        let knownPaths = Set(attachmentPaths(in: existingMessages).map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let orphanedPaths = files
            .filter { !$0.hasDirectoryPath }
            .map { $0.standardizedFileURL.path }
            .filter { !knownPaths.contains($0) }

        return deleteFiles(paths: orphanedPaths)
    }

    static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private static func attachmentPaths(in messages: [ChatMessage]) -> [String] {
        messages.flatMap { message in
            (message.attachmentPaths ?? []) + (message.audioAttachmentPaths ?? [])
        }
    }

    private static func attachmentDirectoryURL(createIfNeeded: Bool) -> URL? {
        let fileManager = FileManager.default
        let folderURL: URL
        if let attachmentDirectoryOverride {
            folderURL = attachmentDirectoryOverride
        } else {
            guard let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            folderURL = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        }

        guard createIfNeeded else {
            return fileManager.fileExists(atPath: folderURL.path) ? folderURL : nil
        }

        if !fileManager.fileExists(atPath: folderURL.path) {
            do {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                Logger.shared.error("Failed to create attachment folder: \(error.localizedDescription)")
                return nil
            }
        }
        return folderURL
    }

    private static func fileSize(path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        if let size = attributes?[.size] as? NSNumber {
            return size.int64Value
        }
        return attributes?[.size] as? Int64 ?? 0
    }
}
