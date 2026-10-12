import AVFoundation
import Foundation

/// Coordinates the temporary audio-session changes needed for microphone capture.
final class AudioSessionCoordinator {
    private struct AudioSessionState {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    private let audioSession: AVAudioSession
    private let logger: Logger
    private var previousState: AudioSessionState?
    private var didApplyRecordingSession = false

    init(
        audioSession: AVAudioSession = .sharedInstance(),
        logger: Logger = .shared
    ) {
        self.audioSession = audioSession
        self.logger = logger
    }

    func startRecordingSession() throws {
        guard !didApplyRecordingSession else { return }

        previousState = AudioSessionState(
            category: audioSession.category,
            mode: audioSession.mode,
            options: audioSession.categoryOptions
        )

        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        didApplyRecordingSession = true
    }

    func stopRecordingSession() {
        guard didApplyRecordingSession || previousState != nil else { return }

        let stateToRestore = previousState
        previousState = nil
        didApplyRecordingSession = false

        var didRestoreState = false
        if let stateToRestore {
            do {
                try audioSession.setCategory(
                    stateToRestore.category,
                    mode: stateToRestore.mode,
                    options: stateToRestore.options
                )
                didRestoreState = true
            } catch {
                logger.error("Failed to restore previous audio session category: \(error.localizedDescription)")
            }
        }

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate recording audio session: \(error.localizedDescription)")
        }

        guard let stateToRestore, !didRestoreState else { return }

        do {
            try audioSession.setCategory(
                stateToRestore.category,
                mode: stateToRestore.mode,
                options: stateToRestore.options
            )
        } catch {
            logger.error("Failed to restore previous audio session category after deactivation: \(error.localizedDescription)")
        }
    }
}
