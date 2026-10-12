import Combine
import Foundation

final class ModelDownloadManager: NSObject, ObservableObject {
    static let shared = ModelDownloadManager()

    @MainActor @Published var activeDownloads: [String: DownloadProgress] = [:]
    @MainActor @Published var downloadedModels: Set<String> = []
    @MainActor @Published var downloadedVariantIds: Set<String> = []
    @MainActor @Published var lastErrorByVariantId: [String: String] = [:]
    @MainActor @Published var latestFailure: DownloadFailure?
    @MainActor @Published var resumableDownloads: Set<String> = []

    struct DownloadProgress {
        let variantId: String
        let definitionId: String
        var progress: Double
        var totalBytes: Int64
        var downloadedBytes: Int64
        var status: String
    }

    struct DownloadFailure: Identifiable {
        let id = UUID()
        let variantId: String
        let message: String
    }

    private struct DownloadPreflight {
        let totalBytes: Int64
    }

    private let artifactStore = LocalArtifactStore()
    private let capabilityService = LocalCapabilityService()
    private let registry = LocalModelRegistry.shared

    private var urlSession: URLSession!
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var mlxDownloadTasks: [String: Task<Void, Never>] = [:]
    private var variantIdForTask: [Int: String] = [:]
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]
    private let lock = NSLock()

    private override init() {
        super.init()

        let configuration = URLSessionConfiguration.background(
            withIdentifier: "Manuilov.AiChat.model-downloads"
        )
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 4
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)

        refreshDownloadedModelsSync()
        Logger.shared.info("ModelDownloadManager initialized with manifest-backed storage")
    }

    @MainActor
    func startDownload(definition: LocalModelDefinition, variant: LocalModelVariant? = nil) async throws {
        let selectedVariant: LocalModelVariant
        if let variant {
            selectedVariant = variant
        } else if let preferred = capabilityService.preferredDownloadVariant(
            for: definition,
            includeExperimental: ModelPreferences.localIncludeExperimental
        ) {
            selectedVariant = preferred
        } else {
            throw DownloadError.noCompatibleVariant
        }

        guard !artifactStore.isVariantDownloaded(selectedVariant.id) else {
            refreshDownloadedModels()
            return
        }
        guard activeDownloads[selectedVariant.id] == nil else {
            return
        }

        switch selectedVariant.downloadSource {
        case .direct(let url):
            clearFailure(for: selectedVariant.id)
            try await startGGUFDownload(variant: selectedVariant, urlString: url)
        case .huggingFaceRepository:
            clearFailure(for: selectedVariant.id)
            try await startMLXDownload(variant: selectedVariant)
        }
    }

    @MainActor
    func cancelDownload(variantId: String) {
        if let task = downloadTasks[variantId] {
            task.cancel(byProducingResumeData: { [weak self] resumeData in
                guard let self, let resumeData, !resumeData.isEmpty else { return }
                try? self.artifactStore.saveResumeData(resumeData, for: variantId)
                Task { @MainActor in
                    self.resumableDownloads.insert(variantId)
                }
            })
            removeVariantId(forTaskIdentifier: task.taskIdentifier)
        }
        if let task = mlxDownloadTasks[variantId] {
            task.cancel()
            mlxDownloadTasks.removeValue(forKey: variantId)
            resumableDownloads.insert(variantId)
        }
        downloadTasks.removeValue(forKey: variantId)
        activeDownloads.removeValue(forKey: variantId)
        clearFailure(for: variantId)
    }

    @MainActor
    func deleteModel(modelId: String) throws {
        try artifactStore.deleteDefinition(modelId)
        refreshDownloadedModels()
    }

    @MainActor
    func deleteVariant(variantId: String) throws {
        try artifactStore.deleteVariant(variantId)
        clearFailure(for: variantId)
        refreshDownloadedModels()
    }

    nonisolated func isModelDownloaded(_ modelId: String) -> Bool {
        artifactStore.isDefinitionDownloaded(modelId)
    }

    nonisolated func isVariantDownloaded(_ variantId: String) -> Bool {
        artifactStore.isVariantDownloaded(variantId)
    }

    nonisolated func downloadedArtifacts(for definitionId: String) -> [LocalArtifactManifest] {
        artifactStore.manifests(for: definitionId)
    }

    nonisolated func setBackgroundCompletionHandler(
        _ handler: @escaping () -> Void,
        for sessionIdentifier: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        backgroundCompletionHandlers[sessionIdentifier] = handler
    }

    @MainActor
    func refreshDownloadedModels() {
        artifactStore.repairManifests()
        let manifests = artifactStore.verifiedManifests()
        downloadedModels = Set(manifests.map(\.definitionId))
        downloadedVariantIds = Set(manifests.map(\.id))
        refreshResumableDownloads()
        AvailableModelsProvider.invalidateCache()
        objectWillChange.send()
    }

    private func refreshDownloadedModelsSync() {
        artifactStore.repairManifests()
        let manifests = artifactStore.verifiedManifests()
        let definitionIds = Set(manifests.map(\.definitionId))
        let variantIds = Set(manifests.map(\.id))

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.downloadedModels = definitionIds
            self.downloadedVariantIds = variantIds
            self.refreshResumableDownloads()
        }
    }

    @MainActor
    private func refreshResumableDownloads() {
        let variants = registry.allDefinitions(includeExperimental: true).flatMap(\.variants)
        resumableDownloads = Set(variants.compactMap { variant in
            if artifactStore.loadResumeData(for: variant.id) != nil {
                return variant.id
            }
            if artifactStore.loadStagingState(for: variant.id) != nil {
                return variant.id
            }
            return nil
        }).subtracting(downloadedVariantIds)
    }

    @MainActor
    private func startGGUFDownload(variant: LocalModelVariant, urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        let preflight = try await preflightGGUFDownload(url: url)
        let requiredBytes = preflight.totalBytes > 0 ? preflight.totalBytes : Int64(variant.sizeMB * 1024 * 1024)
        try preflightDiskSpace(requiredBytes: requiredBytes)

        activeDownloads[variant.id] = DownloadProgress(
            variantId: variant.id,
            definitionId: variant.definitionId,
            progress: 0,
            totalBytes: requiredBytes,
            downloadedBytes: 0,
            status: artifactStore.loadResumeData(for: variant.id) == nil ? "Starting" : "Resuming"
        )

        let task: URLSessionDownloadTask
        if let resumeData = artifactStore.loadResumeData(for: variant.id) {
            task = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            task = urlSession.downloadTask(with: url)
        }
        task.taskDescription = variant.id
        setVariantId(variant.id, forTaskIdentifier: task.taskIdentifier)
        downloadTasks[variant.id] = task
        resumableDownloads.remove(variant.id)
        task.resume()
    }

    @MainActor
    private func startMLXDownload(variant: LocalModelVariant) async throws {
        guard case .huggingFaceRepository(let repoID) = variant.downloadSource else {
            throw DownloadError.invalidURL
        }
        guard mlxDownloadTasks[variant.id] == nil else {
            return
        }

        let files = try await fetchRepositoryFiles(repoID: repoID)
        let requiredFiles = try validateRequiredRepositoryFiles(files)
        let totalBytes = requiredFiles.compactMap(\.size).reduce(0, +)
        let requiredBytes = totalBytes > 0 ? totalBytes : Int64(variant.sizeMB * 1024 * 1024)
        let stagingDir = try artifactStore.prepareResumableStagingDirectory(for: variant)
        let alreadyDownloadedBytes = measuredStagedBytes(in: stagingDir, requiredFiles: requiredFiles)
        try preflightDiskSpace(requiredBytes: max(0, requiredBytes - alreadyDownloadedBytes))

        activeDownloads[variant.id] = DownloadProgress(
            variantId: variant.id,
            definitionId: variant.definitionId,
            progress: requiredBytes > 0 ? Double(alreadyDownloadedBytes) / Double(requiredBytes) : 0,
            totalBytes: requiredBytes,
            downloadedBytes: alreadyDownloadedBytes,
            status: alreadyDownloadedBytes > 0 ? "Resuming files" : "Starting"
        )

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.downloadMLXFiles(
                    variant: variant,
                    repoID: repoID,
                    requiredFiles: requiredFiles,
                    totalBytes: requiredBytes,
                    stagingDir: stagingDir
                )
                try self.artifactStore.finalizeMLXDownload(
                    stagingDirectory: stagingDir,
                    variant: variant,
                    expectedFiles: requiredFiles.map {
                        LocalArtifactExpectedFile(path: $0.path, sizeBytes: $0.size)
                    }
                )
                self.artifactStore.removeStagingArtifacts(for: variant)
                await MainActor.run {
                    self.activeDownloads.removeValue(forKey: variant.id)
                    self.mlxDownloadTasks.removeValue(forKey: variant.id)
                    self.resumableDownloads.remove(variant.id)
                    self.clearFailure(for: variant.id)
                    self.refreshDownloadedModels()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.activeDownloads.removeValue(forKey: variant.id)
                    self.mlxDownloadTasks.removeValue(forKey: variant.id)
                    self.resumableDownloads.insert(variant.id)
                    self.clearFailure(for: variant.id)
                }
            } catch {
                await MainActor.run {
                    self.activeDownloads.removeValue(forKey: variant.id)
                    self.mlxDownloadTasks.removeValue(forKey: variant.id)
                    self.resumableDownloads.insert(variant.id)
                    self.publishFailure(for: variant.id, error: error)
                }
            }
        }
        mlxDownloadTasks[variant.id] = task
        resumableDownloads.remove(variant.id)
    }

    private func fetchRepositoryFiles(repoID: String) async throws -> [HuggingFaceFile] {
        let encodedRepoID = repoID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoID
        guard let url = URL(string: "https://huggingface.co/api/models/\(encodedRepoID)") else {
            throw DownloadError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DownloadError.repositoryManifestFailed("Repository metadata request failed with HTTP \(statusCode).")
        }
        return try JSONDecoder().decode(HuggingFaceModelInfo.self, from: data).siblings
    }

    private func preflightGGUFDownload(url: URL) async throws -> DownloadPreflight {
        if let headResult = try? await performGGUFPreflightRequest(url: url, method: "HEAD", rangeHeader: nil) {
            return headResult
        }

        // Some Hugging Face resolve URLs reject HEAD with 401/403 even though GET works.
        if let rangedGET = try? await performGGUFPreflightRequest(
            url: url,
            method: "GET",
            rangeHeader: "bytes=0-0"
        ) {
            return rangedGET
        }

        if url.host?.contains("huggingface.co") == true {
            Logger.shared.info("⚠️ GGUF preflight could not validate Hugging Face URL, continuing with download task")
            return DownloadPreflight(totalBytes: 0)
        }

        throw DownloadError.preflightFailed("Download server could not be validated before starting the download.")
    }

    private func performGGUFPreflightRequest(
        url: URL,
        method: String,
        rangeHeader: String?
    ) async throws -> DownloadPreflight {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        if let rangeHeader {
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.preflightFailed("Download server returned an invalid response.")
        }

        let successCodes = method == "GET" ? (200 ... 299).contains(httpResponse.statusCode) || httpResponse.statusCode == 206
                                           : (200 ... 299).contains(httpResponse.statusCode)
        guard successCodes else {
            throw DownloadError.preflightFailed("Download server returned HTTP \(httpResponse.statusCode).")
        }

        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("html") {
            throw DownloadError.preflightFailed("Download URL returned HTML instead of a model file.")
        }

        let totalBytes = parseTotalBytes(fromContentRange: httpResponse.value(forHTTPHeaderField: "Content-Range"))
            ?? httpResponse.expectedContentLength
        if totalBytes > 0 && totalBytes < Self.minimumGGUFSizeBytes {
            throw DownloadError.artifactValidationFailed("Remote artifact is too small to be a valid GGUF file.")
        }

        return DownloadPreflight(totalBytes: totalBytes)
    }

    private func parseTotalBytes(fromContentRange contentRange: String?) -> Int64? {
        guard let contentRange,
              let totalPart = contentRange.split(separator: "/").last,
              totalPart != "*",
              let total = Int64(totalPart) else {
            return nil
        }
        return total
    }

    private func validateRequiredRepositoryFiles(_ files: [HuggingFaceFile]) throws -> [HuggingFaceFile] {
        let requiredFiles = files.filter { file in
            file.path.hasSuffix(".json") ||
            file.path.hasSuffix(".safetensors") ||
            file.path == "tokenizer.model" ||
            file.path == "tokenizer.json"
        }

        guard requiredFiles.contains(where: { $0.path == "config.json" }) else {
            throw DownloadError.repositoryManifestFailed("Repository is missing config.json.")
        }
        guard requiredFiles.contains(where: { $0.path == "tokenizer.model" || $0.path == "tokenizer.json" }) else {
            throw DownloadError.repositoryManifestFailed("Repository is missing tokenizer files.")
        }
        guard requiredFiles.contains(where: { $0.path.hasSuffix(".safetensors") }) else {
            throw DownloadError.repositoryManifestFailed("Repository does not contain any .safetensors weights.")
        }

        return requiredFiles
    }

    private func downloadMLXFiles(
        variant: LocalModelVariant,
        repoID: String,
        requiredFiles: [HuggingFaceFile],
        totalBytes: Int64,
        stagingDir: URL
    ) async throws {
        var state = artifactStore.loadStagingState(for: variant.id)
            ?? LocalDownloadStagingState(
                variantId: variant.id,
                definitionId: variant.definitionId,
                sourceURL: variant.downloadSource.urlString,
                totalBytes: totalBytes,
                files: requiredFiles.map {
                    LocalDownloadStagingState.FileState(
                        path: $0.path,
                        expectedSizeBytes: $0.size,
                        downloadedBytes: 0,
                        isComplete: false,
                        attempts: 0,
                        lastError: nil
                    )
                },
                updatedAt: Date()
            )
        let statePaths = Set(state.files.map(\.path))
        let requiredPaths = Set(requiredFiles.map(\.path))
        if state.totalBytes != totalBytes || statePaths != requiredPaths {
            state = LocalDownloadStagingState(
                variantId: variant.id,
                definitionId: variant.definitionId,
                sourceURL: variant.downloadSource.urlString,
                totalBytes: totalBytes,
                files: requiredFiles.map {
                    LocalDownloadStagingState.FileState(
                        path: $0.path,
                        expectedSizeBytes: $0.size,
                        downloadedBytes: 0,
                        isComplete: false,
                        attempts: 0,
                        lastError: nil
                    )
                },
                updatedAt: Date()
            )
        }
        try artifactStore.saveStagingState(state)

        for file in requiredFiles {
            try Task.checkCancellation()
            guard let fileIndex = state.files.firstIndex(where: { $0.path == file.path }) else {
                continue
            }

            let destinationURL = stagingDir.appendingPathComponent(file.path)
            if isStagedFileComplete(destinationURL, expectedSize: file.size) {
                state.files[fileIndex].downloadedBytes = artifactStore.fileSize(at: destinationURL) ?? file.size ?? 0
                state.files[fileIndex].isComplete = true
                state.files[fileIndex].lastError = nil
                state.updatedAt = Date()
                try artifactStore.saveStagingState(state)
                await updateMLXProgress(
                    variant: variant,
                    totalBytes: totalBytes,
                    files: state.files,
                    currentFile: file.path
                )
                continue
            }

            let fileURLString = "https://huggingface.co/\(repoID)/resolve/main/\(file.path)"
            guard let url = URL(string: fileURLString) else {
                throw DownloadError.invalidURL
            }

            var lastError: Error?
            for attempt in 0 ..< Self.maxMLXFileAttempts {
                try Task.checkCancellation()
                state.files[fileIndex].attempts = attempt + 1
                state.files[fileIndex].lastError = nil
                state.updatedAt = Date()
                try artifactStore.saveStagingState(state)

                do {
                    let downloader = ResumableFileDownloader(
                        url: url,
                        destinationURL: destinationURL,
                        expectedSize: file.size
                    ) { [weak self] bytes in
                        guard let self else { return }
                        Task {
                            var progressState = state.files
                            if let index = progressState.firstIndex(where: { $0.path == file.path }) {
                                progressState[index].downloadedBytes = bytes
                            }
                            await self.updateMLXProgress(
                                variant: variant,
                                totalBytes: totalBytes,
                                files: progressState,
                                currentFile: file.path
                            )
                        }
                    }

                    let downloadedBytes = try await downloader.start()
                    state.files[fileIndex].downloadedBytes = downloadedBytes
                    state.files[fileIndex].isComplete = true
                    state.files[fileIndex].lastError = nil
                    state.updatedAt = Date()
                    try artifactStore.saveStagingState(state)
                    await updateMLXProgress(
                        variant: variant,
                        totalBytes: totalBytes,
                        files: state.files,
                        currentFile: file.path
                    )
                    lastError = nil
                    break
                } catch is CancellationError {
                    state.files[fileIndex].downloadedBytes = artifactStore.fileSize(at: destinationURL) ?? 0
                    state.files[fileIndex].lastError = "Download paused."
                    state.updatedAt = Date()
                    try? artifactStore.saveStagingState(state)
                    throw CancellationError()
                } catch {
                    lastError = error
                    state.files[fileIndex].downloadedBytes = artifactStore.fileSize(at: destinationURL) ?? 0
                    state.files[fileIndex].lastError = error.localizedDescription
                    state.updatedAt = Date()
                    try artifactStore.saveStagingState(state)
                    if attempt + 1 < Self.maxMLXFileAttempts {
                        let delaySeconds = UInt64(pow(2.0, Double(attempt)))
                        try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
                    }
                }
            }

            if let lastError {
                throw DownloadError.downloadFailed("\(file.path): \(lastError.localizedDescription)")
            }
        }

        if let validationError = artifactStore.validateMLXDirectory(
            at: stagingDir,
            expectedFiles: requiredFiles.map { LocalArtifactExpectedFile(path: $0.path, sizeBytes: $0.size) }
        ) {
            throw validationError
        }
    }

    private func updateMLXProgress(
        variant: LocalModelVariant,
        totalBytes: Int64,
        files: [LocalDownloadStagingState.FileState],
        currentFile: String
    ) async {
        let downloaded = files.reduce(Int64(0)) { partial, file in
            partial + min(file.downloadedBytes, file.expectedSizeBytes ?? file.downloadedBytes)
        }
        let progress = totalBytes > 0 ? min(1, Double(downloaded) / Double(totalBytes)) : 0
        await MainActor.run {
            self.activeDownloads[variant.id] = DownloadProgress(
                variantId: variant.id,
                definitionId: variant.definitionId,
                progress: progress,
                totalBytes: totalBytes,
                downloadedBytes: downloaded,
                status: "Downloading \(URL(fileURLWithPath: currentFile).lastPathComponent)"
            )
        }
    }

    private func measuredStagedBytes(in stagingDir: URL, requiredFiles: [HuggingFaceFile]) -> Int64 {
        requiredFiles.reduce(Int64(0)) { partial, file in
            let url = stagingDir.appendingPathComponent(file.path)
            let size = artifactStore.fileSize(at: url) ?? 0
            if let expected = file.size {
                return partial + min(size, expected)
            }
            return partial + size
        }
    }

    private func isStagedFileComplete(_ url: URL, expectedSize: Int64?) -> Bool {
        guard let size = artifactStore.fileSize(at: url) else {
            return false
        }
        if let expectedSize {
            return size == expectedSize
        }
        return size > 0
    }

    private func preflightDiskSpace(requiredBytes: Int64) throws {
        let requiredBytes = max(requiredBytes, 0)
        let freeBytes = try availableDiskBytes()
        guard freeBytes >= requiredBytes else {
            throw DownloadError.insufficientDiskSpace(requiredBytes: requiredBytes, availableBytes: freeBytes)
        }
    }

    private func availableDiskBytes() throws -> Int64 {
        let values = try artifactStore.modelsDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        )
        if let importantUsage = values.volumeAvailableCapacityForImportantUsage {
            return importantUsage
        }
        if let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        throw DownloadError.preflightFailed("Could not determine available disk space.")
    }

    @MainActor
    private func clearFailure(for variantId: String) {
        lastErrorByVariantId.removeValue(forKey: variantId)
        if latestFailure?.variantId == variantId {
            latestFailure = nil
        }
    }

    @MainActor
    private func publishFailure(for variantId: String, error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastErrorByVariantId[variantId] = message
        latestFailure = DownloadFailure(variantId: variantId, message: message)
    }

    private func setVariantId(_ variantId: String, forTaskIdentifier taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        variantIdForTask[taskIdentifier] = variantId
    }

    private func variantId(forTaskIdentifier taskIdentifier: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return variantIdForTask[taskIdentifier]
    }

    private func variantId(for downloadTask: URLSessionDownloadTask) -> String? {
        variantId(forTaskIdentifier: downloadTask.taskIdentifier) ?? downloadTask.taskDescription
    }

    private func removeVariantId(forTaskIdentifier taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        variantIdForTask.removeValue(forKey: taskIdentifier)
    }

    private func takeBackgroundCompletionHandler(for sessionIdentifier: String) -> (() -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return backgroundCompletionHandlers.removeValue(forKey: sessionIdentifier)
    }
}

extension ModelDownloadManager {
    private static let maxMLXFileAttempts = 3

    struct HuggingFaceFile: Decodable {
        let rfilename: String
        let size: Int64?

        struct LfsInfo: Decodable {
            let size: Int64?
        }

        enum CodingKeys: String, CodingKey {
            case rfilename
            case size
            case lfs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rfilename = try container.decode(String.self, forKey: .rfilename)
            if let size = try container.decodeIfPresent(Int64.self, forKey: .size) {
                self.size = size
            } else if let lfs = try container.decodeIfPresent(LfsInfo.self, forKey: .lfs) {
                self.size = lfs.size
            } else {
                self.size = nil
            }
        }

        var path: String { rfilename }
    }

    struct HuggingFaceModelInfo: Decodable {
        let siblings: [HuggingFaceFile]
    }
}

private final class ResumableFileDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let destinationURL: URL
    private let expectedSize: Int64?
    private let onProgress: (Int64) -> Void
    private let fileManager: FileManager
    private let queue: OperationQueue

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var continuation: CheckedContinuation<Int64, Error>?
    private var responseError: Error?
    private var currentBytes: Int64 = 0
    private var resumeOffset: Int64 = 0

    init(
        url: URL,
        destinationURL: URL,
        expectedSize: Int64?,
        fileManager: FileManager = .default,
        onProgress: @escaping (Int64) -> Void
    ) {
        self.url = url
        self.destinationURL = destinationURL
        self.expectedSize = expectedSize
        self.fileManager = fileManager
        self.onProgress = onProgress
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    func start() async throws -> Int64 {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        resumeOffset = fileSize(at: destinationURL) ?? 0
        if let expectedSize, resumeOffset == expectedSize {
            onProgress(resumeOffset)
            return resumeOffset
        }
        if let expectedSize, resumeOffset > expectedSize {
            try? fileManager.removeItem(at: destinationURL)
            resumeOffset = 0
        }
        currentBytes = resumeOffset

        var request = URLRequest(url: url)
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 60 * 60
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.dataTask(with: request)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            responseError = DownloadError.downloadFailed("Download server returned an invalid response.")
            completionHandler(.cancel)
            return
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            responseError = DownloadError.downloadFailed("Server returned HTTP \(httpResponse.statusCode).")
            completionHandler(.cancel)
            return
        }

        do {
            if resumeOffset > 0, httpResponse.statusCode != 206 {
                try? fileManager.removeItem(at: destinationURL)
                resumeOffset = 0
                currentBytes = 0
            }
            if !fileManager.fileExists(atPath: destinationURL.path) {
                fileManager.createFile(atPath: destinationURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: destinationURL)
            if resumeOffset > 0 {
                try handle.seekToEnd()
            } else {
                try handle.truncate(atOffset: 0)
            }
            fileHandle = handle
            completionHandler(.allow)
        } catch {
            responseError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try fileHandle?.write(contentsOf: data)
            currentBytes += Int64(data.count)
            onProgress(currentBytes)
        } catch {
            responseError = error
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        session.invalidateAndCancel()

        if let responseError {
            continuation?.resume(throwing: responseError)
        } else if let error {
            if (error as? URLError)?.code == .cancelled {
                continuation?.resume(throwing: CancellationError())
            } else {
                continuation?.resume(throwing: error)
            }
        } else if let expectedSize, currentBytes != expectedSize {
            continuation?.resume(
                throwing: DownloadError.incompleteDownload(
                    "\(destinationURL.lastPathComponent) expected \(expectedSize) bytes, got \(currentBytes) bytes."
                )
            )
        } else if currentBytes <= 0 {
            continuation?.resume(
                throwing: DownloadError.incompleteDownload("\(destinationURL.lastPathComponent) is empty.")
            )
        } else {
            continuation?.resume(returning: currentBytes)
        }
        continuation = nil
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }
}

enum DownloadError: Error, LocalizedError {
    case invalidURL
    case preflightFailed(String)
    case downloadFailed(String)
    case saveFailed
    case noCompatibleVariant
    case artifactValidationFailed(String)
    case repositoryManifestFailed(String)
    case incompleteDownload(String)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid download URL."
        case .preflightFailed(let reason):
            return "Download preflight failed: \(reason)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .saveFailed:
            return "Failed to save model files."
        case .noCompatibleVariant:
            return "No compatible variant is available for this device."
        case .artifactValidationFailed(let reason):
            return "Model artifact is invalid: \(reason)"
        case .repositoryManifestFailed(let reason):
            return "Model repository is incomplete: \(reason)"
        case .incompleteDownload(let reason):
            return "Model download is incomplete: \(reason)"
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
            return "Not enough storage to download this model. Required: \(Self.formatBytes(requiredBytes)); available: \(Self.formatBytes(availableBytes))."
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension ModelDownloadManager: URLSessionDownloadDelegate {
    private static let minimumGGUFSizeBytes: Int64 = 10 * 1024 * 1024

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier,
              let completionHandler = takeBackgroundCompletionHandler(for: identifier) else {
            return
        }

        DispatchQueue.main.async {
            completionHandler()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let variantId = variantId(for: downloadTask),
              let variant = registry.variant(for: variantId, includeExperimental: true) else {
            return
        }

        do {
            if let httpResponse = downloadTask.response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode) {
                throw DownloadError.downloadFailed("Server returned HTTP \(httpResponse.statusCode).")
            }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: location.path),
                  let size = attributes[.size] as? Int64 else {
                throw DownloadError.incompleteDownload("Temporary downloaded file is missing.")
            }

            guard size >= Self.minimumGGUFSizeBytes else {
                throw DownloadError.artifactValidationFailed("Downloaded file is too small to be a valid GGUF artifact.")
            }

            let expectedSize = downloadTask.response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown
            if expectedSize > 0, size < expectedSize {
                throw DownloadError.incompleteDownload("Expected \(expectedSize) bytes, got \(size) bytes.")
            }

            try artifactStore.finalizeGGUFDownload(tempURL: location, variant: variant)
            artifactStore.removeResumeData(for: variant.id)

            Task { @MainActor in
                self.activeDownloads.removeValue(forKey: variant.id)
                self.downloadTasks.removeValue(forKey: variant.id)
                self.removeVariantId(forTaskIdentifier: downloadTask.taskIdentifier)
                self.clearFailure(for: variant.id)
                self.refreshDownloadedModels()
            }
        } catch {
            Task { @MainActor in
                self.activeDownloads.removeValue(forKey: variant.id)
                self.downloadTasks.removeValue(forKey: variant.id)
                self.removeVariantId(forTaskIdentifier: downloadTask.taskIdentifier)
                self.publishFailure(for: variant.id, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let variantId = variantId(for: downloadTask),
              let variant = registry.variant(for: variantId, includeExperimental: true) else {
            return
        }

        let total = max(totalBytesExpectedToWrite, Int64(variant.sizeMB * 1024 * 1024))
        let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0

        Task { @MainActor in
            self.activeDownloads[variant.id] = DownloadProgress(
                variantId: variant.id,
                definitionId: variant.definitionId,
                progress: progress,
                totalBytes: total,
                downloadedBytes: totalBytesWritten,
                status: "Downloading"
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let variantId = variantId(for: downloadTask) else {
            return
        }

        Task { @MainActor in
            if error != nil {
                let resumeData = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
                if let resumeData, !resumeData.isEmpty {
                    try? self.artifactStore.saveResumeData(resumeData, for: variantId)
                    self.resumableDownloads.insert(variantId)
                }

                if let urlError = error as? URLError, urlError.code == .cancelled {
                    self.activeDownloads.removeValue(forKey: variantId)
                    self.downloadTasks.removeValue(forKey: variantId)
                    self.removeVariantId(forTaskIdentifier: downloadTask.taskIdentifier)
                    self.clearFailure(for: variantId)
                    return
                }

                self.activeDownloads.removeValue(forKey: variantId)
                self.downloadTasks.removeValue(forKey: variantId)
                self.removeVariantId(forTaskIdentifier: downloadTask.taskIdentifier)
                self.publishFailure(
                    for: variantId,
                    error: DownloadError.downloadFailed(error?.localizedDescription ?? "Unknown transport error.")
                )
            }
        }
    }
}
