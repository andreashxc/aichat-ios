import Foundation
import os

struct Logger: Sendable {
    static let shared = Logger()

    private let logger = os.Logger(subsystem: "org.example.AiChat", category: "app")

    func info(_ message: String) {
        logger.info("\(message, privacy: .private)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .private)")
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .private)")
    }
}
