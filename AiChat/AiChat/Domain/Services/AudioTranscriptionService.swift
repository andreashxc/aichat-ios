import Foundation
import Speech

enum AudioTranscriptionError: LocalizedError {
    case noFinalTranscription
    case recognitionFailed(String)
    case timedOut(seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .noFinalTranscription:
            return "Audio transcription finished without a final transcript."
        case .recognitionFailed(let message):
            return "Audio transcription failed: \(message)"
        case .timedOut:
            return "Audio transcription timed out before a final result arrived."
        }
    }
}

enum AudioTranscriptionRecognizerEvent {
    case partial(String)
    case final(String)
    case failure(Error)
}

protocol AudioTranscriptionRecognitionTask: AnyObject {
    func cancel()
}

protocol AudioTranscriptionRecognizing: AnyObject {
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }

    func requestAuthorizationIfNeeded() async -> Bool
    func startTranscription(
        fileURL: URL,
        requiresOnDeviceRecognition: Bool,
        shouldReportPartialResults: Bool,
        resultHandler: @escaping (AudioTranscriptionRecognizerEvent) -> Void
    ) throws -> AudioTranscriptionRecognitionTask
}

@MainActor
final class AudioTranscriptionService {
    static let shared = AudioTranscriptionService()

    private let recognizer: AudioTranscriptionRecognizing
    private let timeoutSeconds: TimeInterval

    /// Uses `Locale.current` when the service is created. Changing the app/device locale
    /// after startup requires creating a new service instance to use the new locale.
    init(
        recognizer: AudioTranscriptionRecognizing = SFSpeechURLTranscriptionRecognizer(locale: .current),
        timeoutSeconds: TimeInterval = 60
    ) {
        self.recognizer = recognizer
        self.timeoutSeconds = timeoutSeconds
    }

    func transcribe(
        fileURL: URL,
        mode: AudioTranscriptionModel
    ) async throws -> String {
        try Task.checkCancellation()

        let authorized = await recognizer.requestAuthorizationIfNeeded()
        try Task.checkCancellation()

        guard authorized else {
            throw SpeechRecognizerError.notAuthorized
        }

        guard recognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        let requiresOnDeviceRecognition: Bool
        switch mode {
        case .tiny:
            guard recognizer.supportsOnDeviceRecognition else {
                throw SpeechRecognizerError.recognizerUnavailable
            }
            requiresOnDeviceRecognition = true
        case .base:
            requiresOnDeviceRecognition = false
        }

        return try await runRecognition(
            fileURL: fileURL,
            requiresOnDeviceRecognition: requiresOnDeviceRecognition
        )
    }

    private func runRecognition(
        fileURL: URL,
        requiresOnDeviceRecognition: Bool
    ) async throws -> String {
        let state = AudioTranscriptionContinuationState()
        let timeoutSeconds = timeoutSeconds
        let recognizer = recognizer

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)

                let timeoutTask = Task {
                    let nanoseconds = UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    state.resume(throwing: AudioTranscriptionError.timedOut(seconds: timeoutSeconds))
                }
                state.setTimeoutTask(timeoutTask)

                do {
                    let recognitionTask = try recognizer.startTranscription(
                        fileURL: fileURL,
                        requiresOnDeviceRecognition: requiresOnDeviceRecognition,
                        shouldReportPartialResults: false
                    ) { event in
                        switch event {
                        case .partial:
                            break
                        case .final(let transcript):
                            let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmedTranscript.isEmpty {
                                state.resume(throwing: AudioTranscriptionError.noFinalTranscription)
                            } else {
                                state.resume(returning: transcript)
                            }
                        case .failure(let error):
                            state.resume(throwing: AudioTranscriptionError.recognitionFailed(error.localizedDescription))
                        }
                    }
                    state.setRecognitionTask(recognitionTask)
                } catch {
                    state.resume(throwing: AudioTranscriptionError.recognitionFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            state.resume(throwing: CancellationError())
        }
    }
}

private final class SFSpeechURLTranscriptionRecognizer: AudioTranscriptionRecognizing {
    private let speechRecognizer: SFSpeechRecognizer?

    init(locale: Locale) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool {
        speechRecognizer?.isAvailable == true
    }

    var supportsOnDeviceRecognition: Bool {
        speechRecognizer?.supportsOnDeviceRecognition == true
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized {
            return true
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus == .authorized)
            }
        }
    }

    func startTranscription(
        fileURL: URL,
        requiresOnDeviceRecognition: Bool,
        shouldReportPartialResults: Bool,
        resultHandler: @escaping (AudioTranscriptionRecognizerEvent) -> Void
    ) throws -> AudioTranscriptionRecognitionTask {
        guard let speechRecognizer else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = shouldReportPartialResults
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition

        return speechRecognizer.recognitionTask(with: request) { result, error in
            if let error {
                resultHandler(.failure(error))
                return
            }

            guard let result else { return }

            let transcript = result.bestTranscription.formattedString
            if result.isFinal {
                resultHandler(.final(transcript))
            } else {
                resultHandler(.partial(transcript))
            }
        }
    }
}

extension SFSpeechRecognitionTask: AudioTranscriptionRecognitionTask {}

private final class AudioTranscriptionContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var recognitionTask: AudioTranscriptionRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var didResume = false

    func install(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        if didResume {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func setRecognitionTask(_ recognitionTask: AudioTranscriptionRecognitionTask) {
        lock.lock()
        if didResume {
            lock.unlock()
            recognitionTask.cancel()
            return
        }
        self.recognitionTask = recognitionTask
        lock.unlock()
    }

    func setTimeoutTask(_ timeoutTask: Task<Void, Never>) {
        lock.lock()
        if didResume {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    func resume(returning value: String) {
        let resources = takeResourcesForResume()
        resources.timeoutTask?.cancel()
        resources.recognitionTask?.cancel()
        resources.continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        let resources = takeResourcesForResume()
        resources.timeoutTask?.cancel()
        resources.recognitionTask?.cancel()
        resources.continuation?.resume(throwing: error)
    }

    private func takeResourcesForResume() -> (
        continuation: CheckedContinuation<String, Error>?,
        recognitionTask: AudioTranscriptionRecognitionTask?,
        timeoutTask: Task<Void, Never>?
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !didResume else {
            return (nil, nil, nil)
        }

        didResume = true
        let resources = (continuation, recognitionTask, timeoutTask)
        continuation = nil
        recognitionTask = nil
        timeoutTask = nil
        return resources
    }
}
