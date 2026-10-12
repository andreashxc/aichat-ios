import XCTest
@testable import AiChat

@MainActor
final class AudioTranscriptionServiceTests: XCTestCase {
    func testFinalTranscriptWinsOnlyOnceWhenRecognizerCallsBackAgain() async throws {
        let recognizer = FakeAudioTranscriptionRecognizer()
        let service = AudioTranscriptionService(recognizer: recognizer, timeoutSeconds: 1)
        let fileURL = URL(fileURLWithPath: "/tmp/test.m4a")

        let task = Task {
            try await service.transcribe(fileURL: fileURL, mode: .base)
        }

        await recognizer.waitUntilStarted()
        recognizer.emit(.final("hello world"))
        recognizer.emit(.failure(TestError.extraCallback))

        let transcript = try await task.value
        XCTAssertEqual(transcript, "hello world")
        XCTAssertEqual(recognizer.startCallCount, 1)
        XCTAssertEqual(recognizer.currentTask?.cancelCount, 1)
    }

    func testTimeoutCancelsRecognitionTask() async throws {
        let recognizer = FakeAudioTranscriptionRecognizer()
        let service = AudioTranscriptionService(recognizer: recognizer, timeoutSeconds: 0.01)
        let fileURL = URL(fileURLWithPath: "/tmp/test.m4a")

        do {
            _ = try await service.transcribe(fileURL: fileURL, mode: .base)
            XCTFail("Expected transcription timeout")
        } catch let error as AudioTranscriptionError {
            guard case .timedOut = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        }

        XCTAssertEqual(recognizer.currentTask?.cancelCount, 1)
    }

    func testCancellationCancelsRecognitionTask() async throws {
        let recognizer = FakeAudioTranscriptionRecognizer()
        let service = AudioTranscriptionService(recognizer: recognizer, timeoutSeconds: 1)
        let fileURL = URL(fileURLWithPath: "/tmp/test.m4a")

        let task = Task {
            try await service.transcribe(fileURL: fileURL, mode: .base)
        }

        await recognizer.waitUntilStarted()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(recognizer.currentTask?.cancelCount, 1)
        }
    }

    func testEmptyFinalTranscriptReturnsClearError() async throws {
        let recognizer = FakeAudioTranscriptionRecognizer()
        let service = AudioTranscriptionService(recognizer: recognizer, timeoutSeconds: 1)
        let fileURL = URL(fileURLWithPath: "/tmp/test.m4a")

        let task = Task {
            try await service.transcribe(fileURL: fileURL, mode: .base)
        }

        await recognizer.waitUntilStarted()
        recognizer.emit(.final("   "))

        do {
            _ = try await task.value
            XCTFail("Expected no-final-transcription error")
        } catch let error as AudioTranscriptionError {
            guard case .noFinalTranscription = error else {
                return XCTFail("Expected noFinalTranscription, got \(error)")
            }
            XCTAssertEqual(error.localizedDescription, "Audio transcription finished without a final transcript.")
        }
    }

    func testTinyModeRequiresOnDeviceRecognition() async throws {
        let recognizer = FakeAudioTranscriptionRecognizer()
        let service = AudioTranscriptionService(recognizer: recognizer, timeoutSeconds: 1)
        let fileURL = URL(fileURLWithPath: "/tmp/test.m4a")

        let task = Task {
            try await service.transcribe(fileURL: fileURL, mode: .tiny)
        }

        await recognizer.waitUntilStarted()
        XCTAssertEqual(recognizer.lastRequiresOnDeviceRecognition, true)
        recognizer.emit(.final("local transcript"))

        _ = try await task.value
    }
}

private enum TestError: LocalizedError {
    case extraCallback

    var errorDescription: String? {
        "extra callback"
    }
}

private final class FakeAudioTranscriptionRecognizer: AudioTranscriptionRecognizing {
    var isAvailable = true
    var supportsOnDeviceRecognition = true
    var isAuthorized = true
    private(set) var startCallCount = 0
    private(set) var lastRequiresOnDeviceRecognition: Bool?
    private(set) var currentTask: FakeAudioTranscriptionRecognitionTask?
    private var resultHandler: ((AudioTranscriptionRecognizerEvent) -> Void)?

    func requestAuthorizationIfNeeded() async -> Bool {
        isAuthorized
    }

    func startTranscription(
        fileURL: URL,
        requiresOnDeviceRecognition: Bool,
        shouldReportPartialResults: Bool,
        resultHandler: @escaping (AudioTranscriptionRecognizerEvent) -> Void
    ) throws -> AudioTranscriptionRecognitionTask {
        startCallCount += 1
        lastRequiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.resultHandler = resultHandler

        let task = FakeAudioTranscriptionRecognitionTask()
        currentTask = task
        return task
    }

    func emit(_ event: AudioTranscriptionRecognizerEvent) {
        resultHandler?(event)
    }

    func waitUntilStarted(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10 {
            if resultHandler != nil {
                return
            }
            await Task.yield()
        }
        XCTFail("Recognizer was not started", file: file, line: line)
    }
}

private final class FakeAudioTranscriptionRecognitionTask: AudioTranscriptionRecognitionTask {
    private(set) var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }
}
