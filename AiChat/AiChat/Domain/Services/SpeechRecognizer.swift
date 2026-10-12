import Foundation
import Speech
import AVFoundation
import Combine
import os

/// Service for speech-to-text recognition using Apple's Speech framework
@MainActor
final class SpeechRecognizer: ObservableObject {
    // MARK: - Published State

    /// Current transcribed text
    @Published var transcript: String = ""

    /// Whether speech recognition is currently active
    @Published var isRecording: Bool = false

    /// Current authorization status
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Error message if recognition fails
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let audioSessionCoordinator: AudioSessionCoordinator
    private var inputTapInstalled = false
    private var activeRecognitionID: UUID?
    private let logger = Logger()

    // MARK: - Initialization

    init(locale: Locale = .current, audioSessionCoordinator: AudioSessionCoordinator = AudioSessionCoordinator()) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        self.audioSessionCoordinator = audioSessionCoordinator
        self.authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Public Methods

    /// Request authorization for speech recognition and microphone access
    func requestAuthorization() async -> Bool {
        // Request speech recognition authorization
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        authorizationStatus = speechStatus

        guard speechStatus == .authorized else {
            errorMessage = "Speech recognition not authorized"
            print("⚠️ Speech recognition authorization denied: \(speechStatus.rawValue)")
            return false
        }

        // Request microphone authorization
        let micStatus = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard micStatus else {
            errorMessage = "Microphone access not authorized"
            print("⚠️ Microphone authorization denied")
            return false
        }

        return true
    }

    /// Start recording and transcribing speech
    func startRecording() async throws {
        guard !isRecording, recognitionTask == nil else { return }

        // Ensure we have authorization
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            guard authorized else {
                throw SpeechRecognizerError.notAuthorized
            }
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognizerError.recognizerUnavailable
        }

        do {
            try audioSessionCoordinator.startRecordingSession()

            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let recognitionRequest else {
                throw SpeechRecognizerError.failedToCreateRequest
            }

            recognitionRequest.shouldReportPartialResults = true

            // Configure audio input
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            inputTapInstalled = true

            // Start audio engine
            audioEngine.prepare()
            try audioEngine.start()

            let recognitionID = UUID()
            activeRecognitionID = recognitionID

            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }

                Task { @MainActor in
                    guard self.activeRecognitionID == recognitionID else { return }

                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }

                    if let error {
                        self.logger.error("Recognition error: \(error.localizedDescription)")
                        let readableError = SpeechRecognizerError.recognitionFailed(error.localizedDescription)
                        self.errorMessage = readableError.localizedDescription
                        self.stopRecording()
                        return
                    }

                    // Stop if final result
                    if result?.isFinal == true {
                        self.stopRecording()
                    }
                }
            }

            isRecording = true
            errorMessage = nil
            logger.info("Started speech recognition")
        } catch {
            stopRecording()
            let readableError = SpeechRecognizerError.recordingStartFailed(error.localizedDescription)
            errorMessage = readableError.localizedDescription
            throw readableError
        }
    }

    /// Stop recording and finalize transcription
    func stopRecording() {
        let hadActiveRecording = isRecording || recognitionTask != nil || recognitionRequest != nil || inputTapInstalled || audioEngine.isRunning

        activeRecognitionID = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        audioSessionCoordinator.stopRecordingSession()

        if hadActiveRecording {
            logger.info("Stopped speech recognition")
        }
    }

    /// Reset transcript and error state
    func reset() {
        transcript = ""
        errorMessage = nil
    }
}

// MARK: - Error Types

enum SpeechRecognizerError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case failedToCreateRequest
    case recordingStartFailed(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition or microphone access not authorized. Please enable in Settings."
        case .recognizerUnavailable:
            return "Speech recognizer is not available for your device or locale."
        case .failedToCreateRequest:
            return "Failed to create speech recognition request."
        case .recordingStartFailed(let message):
            return "Could not start voice input: \(message)"
        case .recognitionFailed(let message):
            return "Speech recognition failed: \(message)"
        }
    }
}
